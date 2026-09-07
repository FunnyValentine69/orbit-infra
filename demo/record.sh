#!/usr/bin/env bash
set -euo pipefail

if [ "${DEMO_BOUNDARY:-}" != 1 ]; then
  echo "demo: run make demo; demo/record.sh must be started through demo/env.sh" >&2
  exit 1
fi
# shellcheck source=demo/lib.sh
source demo/lib.sh

CURRENT_PHASE=

phase_begin() {
  CURRENT_PHASE=$1
}

phase_ok() {
  printf '%s:ok\n' "$CURRENT_PHASE" >> "$RUN/lifecycle.log"
  CURRENT_PHASE=
}

phase_fail() {
  if [ -n "${RUN:-}" ] && [ -n "$CURRENT_PHASE" ]; then
    printf '%s:fail\n' "$CURRENT_PHASE" >> "$RUN/lifecycle.log"
    CURRENT_PHASE=
  fi
}

die() {
  phase_fail
  echo "demo: $1" >&2
  exit 1
}

guard() {
  local assignment name value
  [ "${DEMO_BOUNDARY:-}" = 1 ] || \
    die "run make demo; demo/record.sh must be started through demo/env.sh"
  for assignment in $DEMO_ENV_FIXED; do
    name=${assignment%%=*}
    value=${assignment#*=}
    [ "${!name-}" = "$value" ] || \
      die "constructed environment differs from DEMO_ENV_FIXED: $name"
  done
  [ -n "${OPERATOR_CIDR:-}" ] || die "OPERATOR_CIDR unset"
  cidr_in_test_net_3 "$OPERATOR_CIDR" || \
    die "set OPERATOR_CIDR to a network within 203.0.113.0/24 with prefix /24 to /32, e.g. OPERATOR_CIDR=203.0.113.0/24 make demo"
}

setup() {
  local repo_root
  repo_root=${DEMO_REPO_ROOT:-$PWD}
  cd -- "$repo_root"
  DEMO_DOC=${DEMO_DOC:-docs/assets/DEMO_PROVENANCE.md}
  DEMO_GIF=${DEMO_GIF:-docs/assets/demo.gif}
  mkdir -p demo/out docs/assets
  RUN=$(mktemp -d demo/out/run-XXXXXXXX)
  export RUN
  touch "$RUN/.started"
  : > "$RUN/lifecycle.log"
  printf '%s\n' 'guard:ok' 'setup:ok' >> "$RUN/lifecycle.log"
}

state_list() {
  local out err rc
  err=$(mktemp "$RUN/state-list-error-XXXXXXXX") || {
    echo "demo: mktemp failed" >&2
    return 1
  }
  if out=$(env TF_DATA_DIR=.terraform-localstack \
    terraform -chdir="$PREVIEW_ROOT" state list 2>"$err"); then
    rc=0
  else
    rc=$?
    # Terraform's canonical diagnostic for an absent state is
    # "No state file was found!" followed by an explanatory paragraph;
    # accept it only with empty stdout and no other error line.
    if [ -z "$out" ] && awk '
      NF && first == "" { first = $0; next }
      NF && ($0 ~ /^Error/ || $0 ~ /Error:/) { bad = 1 }
      END { exit (bad || first !~ /^No state file was found!?$/) }
    ' "$err"; then
      rc=0
    else
      cat "$err" >&2
    fi
  fi
  rm -f "$err"
  printf '%s' "$out"
  return "$rc"
}

assert_generator_clean() {
  generator_clean_check . || die "generator inputs are not clean (reason above); commit or remove them before recording"
}

terraform_input_name() {
  case "$1" in
    *.tf|*.tf.json|*.tfvars|*.tfvars.json) return 0 ;;
    *) return 1 ;;
  esac
}

assert_execution_root() {
  local source_list destination_list source destination name
  source_list="$RUN/source-terraform-inputs.bin"
  destination_list="$RUN/destination-terraform-inputs.bin"
  find envs/preview -maxdepth 1 -type f -print0 > "$source_list" || \
    die "could not inspect envs/preview"
  find "$PREVIEW_ROOT" -maxdepth 1 ! -type d ! -name . -print0 > "$destination_list" || \
    die "could not inspect $PREVIEW_ROOT"

  while IFS= read -r -d '' destination; do
    name=${destination##*/}
    terraform_input_name "$name" || continue
    if [ ! -f "$destination" ] || [ -L "$destination" ]; then
      die "non-regular terraform input in execution root: $name"
    fi
  done < "$destination_list"

  while IFS= read -r -d '' source; do
    name=${source##*/}
    [ "$name" != backend_override.tf ] || continue
    terraform_input_name "$name" || continue
    destination="$PREVIEW_ROOT/$name"
    [ -f "$destination" ] || \
      die "execution root differs from envs/preview: $name"
    cmp -s "$source" "$destination" || \
      die "execution root differs from envs/preview: $name"
  done < "$source_list"

  while IFS= read -r -d '' destination; do
    name=${destination##*/}
    [ "$name" != backend_override.tf ] || continue
    terraform_input_name "$name" || continue
    source="envs/preview/$name"
    [ -f "$source" ] || \
      die "execution root differs from envs/preview: $name"
  done < "$destination_list"
}

preflight() {
  local existing
  phase_begin preflight
  command -v vhs >/dev/null || die "vhs is required"
  command -v ffprobe >/dev/null || die "ffprobe is required"
  command -v ffmpeg >/dev/null || die "ffmpeg is required"

  curl -sf localhost:4566/_localstack/health >/dev/null || \
    die "LocalStack is not reachable on localhost:4566"
  docker image inspect placeholder:local >/dev/null 2>&1 || \
    die "placeholder:local image missing; run make placeholder-build"
  aws s3api head-bucket --bucket orbit-infra-79s5rw-tfstate >/dev/null 2>&1 || \
    die "state bucket missing; run make bootstrap-apply TARGET=localstack first"

  assert_generator_clean
  GENERATOR_COMMIT=$(git rev-parse --short=7 HEAD) || \
    die "could not resolve generator commit"
  make render-localstack-backend >/dev/null || die "render-localstack-backend failed"
  assert_execution_root
  env TF_DATA_DIR=.terraform-localstack terraform -chdir="$PREVIEW_ROOT" \
    init -reconfigure -input=false > "$RUN/preflight-init.log" 2>&1 || \
    die "terraform init failed (see $RUN/preflight-init.log)"

  existing=$(state_list) || die "terraform state list failed"
  [ -z "$existing" ] || \
    die "environment demo already has state; run make destroy TARGET=localstack ENV_ID=demo first"

  {
    vhs --version
    ttyd --version 2>&1 | head -1
    ffmpeg -version | head -1
    terraform version | head -1
    curl -sf localhost:4566/_localstack/health | \
      jq -er '.version | select(type=="string" and length>0)'
  } > "$RUN/versions.txt" || die "could not record tool versions"
  [ "$(grep -c . "$RUN/versions.txt")" -eq 5 ] || \
    die "tool version capture incomplete"
  cat "$RUN/versions.txt" || die "could not print tool versions"
  phase_ok
}

record() {
  phase_begin record
  if [ "${DEMO_INJECT_FAIL:-}" = post-apply ]; then
    awk '/^# DEMO-SECTION destroy/{exit} {print}' demo/demo.tape | \
      sed "s#demo/out/#$RUN/#g" > "$RUN/demo.tape" || \
      die "could not generate the run tape"
  else
    sed "s#demo/out/#$RUN/#g" demo/demo.tape > "$RUN/demo.tape" || \
      die "could not generate the run tape"
  fi
  vhs "$RUN/demo.tape" || die "vhs failed"
  phase_ok
}

inject_check() {
  local live
  phase_begin inject_check
  if [ "${DEMO_INJECT_FAIL:-}" = post-apply ]; then
    live=$(state_list) || die "state list failed"
    [ -n "$live" ] || die "injection expected live state but found none"
    printf '%s\n' "$live" | sed -n '1,5p'
    die "injected failure after apply"
  fi
  phase_ok
}

assert_steps() {
  local expected produced step value after file name
  phase_begin assert_steps
  expected="$RUN/expected-steps.txt"
  produced="$RUN/produced-steps.txt"
  tape_steps "$RUN/demo.tape" | sort > "$expected"
  : > "$produced"
  for file in "$RUN"/*.rc; do
    [ -e "$file" ] || continue
    name=${file##*/}
    printf '%s\n' "${name%.rc}" >> "$produced"
  done
  sort -o "$produced" "$produced"
  cmp -s "$expected" "$produced" || \
    die "step rc set differs from tape markers"
  while IFS= read -r step; do
    value=$(cat "$RUN/$step.rc")
    [ "$value" = 0 ] || die "$step.rc was not 0"
  done < "$expected"

  [ -f "$RUN/env.ok" ] && [ "$(cat "$RUN/env.ok")" = 1 ] || \
    die "RUN did not reach the recorded shell"
  grep -q '^Plan:' "$RUN/plan.log" || die "plan.log missing 'Plan:' line"
  grep -q 'Apply complete' "$RUN/apply.log" || \
    die "apply.log missing 'Apply complete'"
  grep -q 'Destroy complete' "$RUN/destroy.log" || \
    die "destroy.log missing 'Destroy complete'"

  after=$(state_list) || die "terraform state list failed after the recorded destroy"
  [ -z "$after" ] || die "state is not empty after the recorded destroy"
  phase_ok
}

inspect_artifact() {
  local size duration frame_info frames frame_rate minimum_frames floor
  local local_user local_host
  phase_begin inspect_artifact
  [ -s "$RUN/demo.gif" ] || die "demo.gif missing or empty"
  [ "$RUN/demo.gif" -nt "$RUN/.started" ] || \
    die "demo.gif mtime predates run start"
  size=$(wc -c < "$RUN/demo.gif" | tr -d ' ')

  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 \
    "$RUN/demo.gif")
  frame_info=$(ffprobe -v error -count_frames -select_streams v:0 \
    -show_entries stream=nb_read_frames,r_frame_rate \
    -of default=noprint_wrappers=1 "$RUN/demo.gif")
  frames=$(printf '%s\n' "$frame_info" | sed -n 's/^nb_read_frames=//p')
  frame_rate=$(printf '%s\n' "$frame_info" | sed -n 's/^r_frame_rate=//p')
  [[ "$frames" =~ ^[0-9]+$ ]] && [ "$frames" -gt 0 ] || \
    die "demo.gif has no frames"
  ffmpeg -v error -i "$RUN/demo.gif" -f null - \
    2> "$RUN/ffmpeg-check.err" || \
    die "demo.gif does not decode cleanly (see $RUN/ffmpeg-check.err)"
  floor=$(tape_expected_seconds "$RUN/demo.tape") || \
    die "could not derive demo.tape duration floor"
  awk -v duration="$duration" -v floor="$floor" \
    'BEGIN { if (duration + 0 < floor + 0) exit 1 }' || \
    die "demo.gif duration $duration s is below tape-derived floor $floor s"
  if ! minimum_frames=$(awk -v floor="$floor" -v rate="$frame_rate" '
    BEGIN {
      if (split(rate, ratio, "/") != 2 ||
          ratio[1] !~ /^[0-9]+$/ || ratio[2] !~ /^[0-9]+$/ ||
          ratio[1] + 0 <= 0 || ratio[2] + 0 <= 0) exit 1
      split(floor, seconds, ".")
      scale=1
      for (i=1; i <= length(seconds[2]); i++) scale *= 10
      floor_units=(seconds[1] * scale) + seconds[2]
      numerator=floor_units * ratio[1]
      denominator=scale * ratio[2]
      minimum=int(numerator / denominator)
      if (minimum * denominator < numerator) minimum++
      print minimum
    }
  '); then
    die "demo.gif has no usable frame rate"
  fi
  [ "$frames" -ge "$minimum_frames" ] || \
    die "demo.gif has $frames frames, below the floor $minimum_frames for $floor s at $frame_rate fps"

  grep -qE '^Plan: [0-9]+ to add' "$RUN/demo.txt" || \
    die "demo.txt missing 'Plan: ' line"
  grep -qE '^Apply complete! Resources: [0-9]+ added' "$RUN/demo.txt" || \
    die "demo.txt missing 'Apply complete'"
  grep -qE '^Destroy complete! Resources: [0-9]+ destroyed' "$RUN/demo.txt" || \
    die "demo.txt missing 'Destroy complete'"
  grep -qE '^PASS: conftest-gate suite' "$RUN/demo.txt" || \
    die "demo.txt missing 'PASS: conftest-gate suite'"
  grep -q '^aws_' "$RUN/demo.txt" || \
    die "demo.txt missing state list output (no line starting with aws_)"
  grep -qi 'localstack' "$RUN/demo.txt" || \
    die "demo.txt missing localstack status output"
  grep -qE '\b(ecs|elbv2|s3)\b.*(running|available)' "$RUN/demo.txt" || \
    die "demo.txt lacks a LocalStack service row"

  local_user=$(id -un)
  local_host=$(hostname -s 2>/dev/null || hostname)
  if grep -qE '/Users/|/home/|AKIA|@' "$RUN/demo.txt"; then
    die "demo.txt contains environment-specific text (path/access-key/email pattern); not publishing"
  fi
  if grep -oE '[0-9]{12}' "$RUN/demo.txt" | grep -vq 000000000000; then
    die "demo.txt contains environment-specific text (12-digit account number); not publishing"
  fi
  if grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$RUN/demo.txt" | \
    grep -vqE '^203\.0\.113\.|^127\.0\.0\.1$|^10\.|^0\.0\.0\.0$'; then
    die "demo.txt contains environment-specific text (non-allowlisted IP address); not publishing"
  fi
  if grep -qiF "$local_user" "$RUN/demo.txt"; then
    die "demo.txt contains environment-specific text (local username); not publishing"
  fi
  if grep -qiF "$local_host" "$RUN/demo.txt"; then
    die "demo.txt contains environment-specific text (local hostname); not publishing"
  fi

  GIF_SIZE=$size
  GIF_DURATION=$duration
  GIF_FRAMES=$frames
  phase_ok
}

build_manifest() {
  local vhs_version ttyd_version ffmpeg_version terraform_version localstack_version
  local recorded_from recorder recorded_on plan_line apply_line destroy_line sha
  phase_begin build_manifest
  vhs_version=$(sed -n '1p' "$RUN/versions.txt" | sed -E 's/^[^0-9]*//')
  ttyd_version=$(sed -n '2p' "$RUN/versions.txt" | sed -E 's/^[^0-9]*//')
  ffmpeg_version=$(sed -n '3p' "$RUN/versions.txt" | sed -E 's/^[^0-9]*//; s/ .*//')
  terraform_version=$(sed -n '4p' "$RUN/versions.txt" | sed -E 's/^[^0-9]*//')
  localstack_version=$(sed -n '5p' "$RUN/versions.txt")
  recorded_from="LocalStack $localstack_version, Terraform $terraform_version"
  recorder="vhs $vhs_version, ttyd $ttyd_version, ffmpeg $ffmpeg_version"
  recorded_on=$(date -u +%F)
  plan_line=$(grep -m1 '^Plan:' "$RUN/plan.log")
  apply_line=$(grep -m1 '^Apply complete' "$RUN/apply.log")
  destroy_line=$(grep -m1 '^Destroy complete' "$RUN/destroy.log")
  sha=$(shasum -a 256 "$RUN/demo.gif" | awk '{print $1}')

  {
    printf 'recorded_from=%s\n' "$recorded_from"
    printf 'recorded_on=%s\n' "$recorded_on"
    printf 'generator_commit=%s (the tree at this commit holds every path in DEMO_GENERATOR_PATHS)\n' "$GENERATOR_COMMIT"
    printf 'recorder=%s\n' "$recorder"
    # shellcheck disable=SC2016
    printf 'command=`OPERATOR_CIDR=%s make demo` from the repository root\n' "$OPERATOR_CIDR"
    printf 'environment=ENV_ID=demo, TARGET=localstack, workspace default, CLI config empty, operator CIDR %s (TEST-NET-3, /24 to /32)\n' "$OPERATOR_CIDR"
    # shellcheck disable=SC2016
    printf 'plan_apply_destroy=`%s`; `%s`; `%s`\n' "$plan_line" "$apply_line" "$destroy_line"
    printf 'artifact=%s bytes, %s s, %s frames\n' "$GIF_SIZE" "$GIF_DURATION" "$GIF_FRAMES"
    printf 'artifact_sha256=%s\n' "$sha"
  } > "$RUN/provenance.env"
  phase_ok
}

manifest_value() {
  local key=$1
  sed -n "s/^${key}=//p" "$RUN/provenance.env"
}

rewrite_provenance_row() {
  local key=$1
  local field=$2
  local count value replacement output
  count=$(grep -c "^| $field |" "$RUN/DEMO_PROVENANCE.md" || true)
  [ "$count" -eq 1 ] || \
    die "required provenance row $field count was $count"
  value=$(manifest_value "$key")
  replacement="| $field | $value |"
  output="$RUN/DEMO_PROVENANCE.next"
  awk -v prefix="| $field |" -v replacement="$replacement" \
    'index($0, prefix) == 1 { print replacement; next } { print }' \
    "$RUN/DEMO_PROVENANCE.md" > "$output" || \
    die "could not render provenance row $field"
  mv "$output" "$RUN/DEMO_PROVENANCE.md"
}

render_provenance() {
  phase_begin render_provenance
  cp "$DEMO_DOC" "$RUN/DEMO_PROVENANCE.md" || \
    die "could not copy provenance template"
  rewrite_provenance_row recorded_from recorded_from
  rewrite_provenance_row recorded_on recorded_on
  rewrite_provenance_row generator_commit 'generator commit'
  rewrite_provenance_row recorder recorder
  rewrite_provenance_row command command
  rewrite_provenance_row environment environment
  rewrite_provenance_row plan_apply_destroy 'plan / apply / destroy'
  rewrite_provenance_row artifact artifact
  rewrite_provenance_row artifact_sha256 'artifact sha256'
  phase_ok
}

teardown() {
  local rc left
  if [ "${TEARDOWN_RC+x}" = x ]; then
    return "$TEARDOWN_RC"
  fi
  phase_begin teardown
  rc=0
  if ! make destroy > "$RUN/cleanup.log" 2>&1; then
    echo "demo: cleanup destroy failed (see $RUN/cleanup.log)" >&2
    rc=1
  fi
  if left=$(state_list 2>> "$RUN/cleanup.log"); then
    if [ -n "$left" ]; then
      printf '%s\n' "$left" >> "$RUN/cleanup.log"
      echo "demo: cleanup left state behind (see $RUN/cleanup.log)" >&2
      rc=1
    fi
  else
    echo "demo: cleanup state check failed (see $RUN/cleanup.log)" >&2
    rc=1
  fi
  TEARDOWN_RC=$rc
  if [ "$rc" -eq 0 ]; then
    phase_ok
  else
    phase_fail
  fi
  return "$rc"
}

publish() {
  phase_begin publish
  mv "$RUN/demo.gif" "$DEMO_GIF"
  mv "$RUN/DEMO_PROVENANCE.md" "$DEMO_DOC"
  phase_ok
  echo "demo: $DEMO_GIF size=$GIF_SIZE duration=$GIF_DURATION frames=$GIF_FRAMES run=$RUN versions=$RUN/versions.txt"
}

main() {
  guard
  setup
  preflight
  trap on_abort EXIT
  record
  inject_check
  assert_steps
  inspect_artifact
  build_manifest
  generator_clean_check . "$GENERATOR_COMMIT" || \
    die "generator inputs changed during the recording; not publishing"
  render_provenance
  teardown || die "teardown failed; not publishing (see $RUN/cleanup.log)"
  publish
  trap - EXIT
  exit 0
}

# shellcheck disable=SC2329
on_abort() {
  local rc=$?
  phase_fail
  teardown || rc=1
  trap - EXIT
  exit "$rc"
}

main "$@"
