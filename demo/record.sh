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

load_recording_config() {
  local key value
  CONFIG_TAPE=
  CONFIG_DOC=
  CONFIG_GIF=
  CONFIG_ENV_ID=
  CONFIG_KIND=
  while IFS='=' read -r key value; do
    case "$key" in
      TAPE) CONFIG_TAPE=$value ;;
      DOC) CONFIG_DOC=$value ;;
      GIF) CONFIG_GIF=$value ;;
      ENV_ID) CONFIG_ENV_ID=$value ;;
      KIND) CONFIG_KIND=$value ;;
      *) die "invalid recording config key: $key" ;;
    esac
  done < <(demo_recording_config "${DEMO_NAME:-demo}")
  [ -n "$CONFIG_TAPE" ] && [ -n "$CONFIG_DOC" ] && \
    [ -n "$CONFIG_GIF" ] && [ -n "$CONFIG_KIND" ] || \
    die "recording config is incomplete"
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
  load_recording_config
  if [ -n "$CONFIG_ENV_ID" ]; then
    [ "${ENV_ID:-}" = "$CONFIG_ENV_ID" ] || \
      die "constructed environment differs from recording config: ENV_ID"
    [ "${PREVIEW_ROOT:-}" = ".preview-runs/$CONFIG_ENV_ID" ] || \
      die "constructed environment differs from recording config: PREVIEW_ROOT"
    [ -n "${OPERATOR_CIDR:-}" ] || die "OPERATOR_CIDR unset"
    cidr_in_test_net_3 "$OPERATOR_CIDR" || \
      die "set OPERATOR_CIDR to a network within 203.0.113.0/24 with prefix /24 to /32, e.g. OPERATOR_CIDR=203.0.113.0/24 make demo"
  elif [ "${ENV_ID+x}" = x ] || [ "${PREVIEW_ROOT+x}" = x ]; then
    die "constructed environment differs from recording config: environment must be unset"
  fi
}

setup() {
  local repo_root
  repo_root=${DEMO_REPO_ROOT:-$PWD}
  cd -- "$repo_root"
  load_recording_config
  DEMO_TAPE=$CONFIG_TAPE
  DEMO_DOC=$CONFIG_DOC
  DEMO_GIF=$CONFIG_GIF
  RECORDING_KIND=$CONFIG_KIND
  case "$RECORDING_KIND" in
    lifecycle) DEMO_TEMPLATE=demo/provenance/lifecycle.md ;;
    lease) DEMO_TEMPLATE=demo/provenance/lease.md ;;
    verify) DEMO_TEMPLATE=demo/provenance/supply.md ;;
    *) die "unsupported recording kind: $RECORDING_KIND" ;;
  esac
  mkdir -p demo/out docs/assets
  RUN=$(mktemp -d demo/out/run-XXXXXXXX)
  export RUN
  DEMO_OWNER="demo-recording-${RUN##*/}"
  export DEMO_OWNER
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
    terraform -chdir="$PREVIEW_ROOT" state list -no-color 2>"$err"); then
    rc=0
  else
    rc=$?
    # Terraform's canonical diagnostic for an absent state (plain text only with -no-color) is
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

list_recording_state_versions() {
  local bucket=$1
  local prefix=$2
  local key_marker=""
  local version_marker=""
  local prior_token=""
  local response is_truncated next_key next_version token
  local inventory='{"Versions":[],"DeleteMarkers":[]}'
  local -a args

  while :; do
    args=(
      s3api list-object-versions --bucket "$bucket" --prefix "$prefix"
      --output json --no-paginate
    )
    if [ -n "$key_marker" ]; then
      args+=(--key-marker "$key_marker")
      if [ -n "$version_marker" ]; then
        args+=(--version-id-marker "$version_marker")
      fi
    fi
    if ! response="$(scripts/aws-cli.sh "${args[@]}")"; then
      echo "could not list retained state versions" >&2
      return 1
    fi
    if ! jq -e '
      type == "object"
      and (.IsTruncated | type == "boolean")
      and ((has("Versions") | not) or (.Versions | type == "array"))
      and ((has("DeleteMarkers") | not) or (.DeleteMarkers | type == "array"))
      and all((.Versions // [])[], (.DeleteMarkers // [])[];
        type == "object" and (.Key | type == "string"))
    ' <<< "$response" >/dev/null 2>&1; then
      echo "list-object-versions returned malformed output" >&2
      return 1
    fi
    if ! inventory="$(jq -c --argjson page "$response" '
      .Versions += ($page.Versions // [])
      | .DeleteMarkers += ($page.DeleteMarkers // [])
    ' <<< "$inventory")"; then
      echo "could not combine retained state inventory" >&2
      return 1
    fi
    is_truncated="$(jq -r '.IsTruncated' <<< "$response")"
    [ "$is_truncated" = true ] || break
    if ! next_key="$(
      jq -er '.NextKeyMarker | select(type == "string" and length > 0)' \
        <<< "$response"
    )"; then
      echo "truncated state-version response has no NextKeyMarker" >&2
      return 1
    fi
    next_version="$(jq -r '.NextVersionIdMarker // empty' <<< "$response")"
    token="${next_key}|${next_version}"
    if [ "$token" = "$prior_token" ]; then
      echo "state-version pagination did not advance" >&2
      return 1
    fi
    prior_token=$token
    key_marker=$next_key
    version_marker=$next_version
  done
  printf '%s\n' "$inventory"
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
  local existing lease_json lease_error lease_rc lease_status
  phase_begin preflight
  command -v vhs >/dev/null || die "vhs is required"
  command -v ffmpeg >/dev/null || die "ffmpeg is required"
  command -v ffprobe >/dev/null || die "ffprobe is required"

  if [ "$RECORDING_KIND" = verify ]; then
    command -v jq >/dev/null || die "jq is required"
    assert_generator_clean
    GENERATOR_COMMIT=$(git rev-parse --short=7 HEAD) || \
      die "could not resolve generator commit"
    {
      vhs --version
      ffmpeg -version | head -1
      jq --version
    } > "$RUN/versions.txt" || die "could not record tool versions"
    [ "$(grep -c . "$RUN/versions.txt")" -eq 3 ] || \
      die "tool version capture incomplete"
    cat "$RUN/versions.txt" || die "could not print tool versions"
    phase_ok
    return
  fi

  curl -sf localhost:4566/_localstack/health >/dev/null || \
    die "LocalStack is not reachable on localhost:4566"
  docker image inspect placeholder:local >/dev/null 2>&1 || \
    die "placeholder:local image missing; run make placeholder-build"
  aws s3api head-bucket --bucket orbit-infra-79s5rw-tfstate >/dev/null 2>&1 || \
    die "state bucket missing; run make bootstrap-apply TARGET=localstack first"

  if [ "$RECORDING_KIND" = lease ]; then
    lease_error="$RUN/preflight-lease.err"
    set +e
    lease_json="$(scripts/lease.sh get "$ENV_ID" 2> "$lease_error")"
    lease_rc=$?
    set -e
    if [ "$lease_rc" -eq 0 ]; then
      lease_status="$(jq -r '.status // empty' <<< "$lease_json")"
      case "$lease_status" in
        closed|deleted) ;;
        open|closing|cleanup_failed)
          die "environment $ENV_ID has lease status '$lease_status'; close it before recording"
          ;;
        *) die "environment $ENV_ID has invalid lease status '$lease_status'" ;;
      esac
    elif [ "$lease_rc" -ne 1 ] || \
         ! grep -Fxq "lease.sh: no lease for $ENV_ID" "$lease_error"; then
      die "could not read lease for $ENV_ID"
    fi
  fi

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
    die "environment $ENV_ID already has state; run make destroy TARGET=localstack ENV_ID=$ENV_ID first"

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
  if [ "$RECORDING_KIND" = lifecycle ] && \
     [ "${DEMO_INJECT_FAIL:-}" = post-apply ]; then
    awk '/^# DEMO-SECTION destroy/{exit} {print}' "$DEMO_TAPE" | \
      sed "s#demo/out/#$RUN/#g" > "$RUN/demo.tape" || \
      die "could not generate the run tape"
  else
    sed "s#demo/out/#$RUN/#g" "$DEMO_TAPE" > "$RUN/demo.tape" || \
      die "could not generate the run tape"
  fi
  vhs "$RUN/demo.tape" || die "vhs failed"
  phase_ok
}

inject_check() {
  local live
  phase_begin inject_check
  if [ "$RECORDING_KIND" = lifecycle ] && [ "${DEMO_INJECT_FAIL:-}" = post-apply ]; then
    live=$(state_list) || die "state list failed"
    [ -n "$live" ] || die "injection expected live state but found none"
    printf '%s\n' "$live" | sed -n '1,5p'
    die "injected failure after apply"
  fi
  phase_ok
}

assert_steps() {
  local expected produced step value after file name final_lease inventory
  local version_count marker_count state_bucket state_key
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
  case "$RECORDING_KIND" in
    lifecycle)
      grep -q '^Plan:' "$RUN/plan.log" || die "plan.log missing 'Plan:' line"
      grep -q 'Apply complete' "$RUN/apply.log" || \
        die "apply.log missing 'Apply complete'"
      grep -q 'Destroy complete' "$RUN/destroy.log" || \
        die "destroy.log missing 'Destroy complete'"
      after=$(state_list) || die "terraform state list failed after the recorded destroy"
      [ -z "$after" ] || die "state is not empty after the recorded destroy"
      ;;
    lease)
      grep -Fxq 'Plan: 61 to add, 0 to change, 0 to destroy.' \
        "$RUN/plan.log" || die "plan.log missing the expected resource count"
      grep -Fxq 'Apply complete! Resources: 61 added, 0 changed, 0 destroyed.' \
        "$RUN/apply.log" || die "apply.log missing the expected resource count"
      [ -s "$RUN/lease.expected" ] && [ -s "$RUN/lease.generation" ] || \
        die "lease generation capture is incomplete"
      [ "$(cat "$RUN/lease.expected")" = "$(cat "$RUN/lease.generation")" ] || \
        die "opened generation differs from the expected next generation"
      grep -Fxq "status=open generation=$(cat "$RUN/lease.generation")" \
        "$RUN/open.log" || die "open.log lacks the expected generation"
      grep -Fq '"status": "open"' "$RUN/lease-active.log" || \
        die "lease-active.log lacks open status"
      grep -Fxq "close-env.sh: $ENV_ID stage 1 complete; lease remains 'closing' for the sweeper" \
        "$RUN/close.log" || die "close.log lacks the Stage-1 completion line"
      tail -n 1 "$RUN/sweep.log" | grep -Fxq 'final_status=closed' || \
        die "sweep.log lacks the closed terminal status"
      final_lease="$(scripts/lease.sh get "$ENV_ID")" || \
        die "could not read the final lease"
      jq -e --arg owner "$DEMO_OWNER" \
        --argjson generation "$(cat "$RUN/lease.generation")" '
          .status == "closed" and .owner == $owner and .generation == $generation
        ' <<< "$final_lease" >/dev/null || \
        die "final lease is not this run's closed generation"
      state_bucket="$(sed -n \
        "s/^LEASE_BUCKET=\"\${LEASE_BUCKET:-\\([^\"]*\\)}\"$/\\1/p" scripts/lease.sh)"
      [ -n "$state_bucket" ] || die "could not resolve the lease state bucket"
      state_key="envs/preview/$ENV_ID.tfstate"
      inventory="$(list_recording_state_versions \
        "$state_bucket" "envs/preview/$ENV_ID")" || \
        die "could not inventory retained state versions"
      version_count="$(jq --arg key "$state_key" '[(.Versions // [])[] | select(.Key == $key or .Key == ($key + ".tflock"))] | length' <<< "$inventory")"
      marker_count="$(jq --arg key "$state_key" '[(.DeleteMarkers // [])[] | select(.Key == $key or .Key == ($key + ".tflock"))] | length' <<< "$inventory")"
      [ "$version_count" -eq 0 ] && [ "$marker_count" -eq 0 ] || \
        die "state or lock versions remain after Stage 2"
      FINAL_STATUS=closed
      VERSIONS_REMAINING=0
      touch "$RUN/final-inventory.complete"
      PRE_OPEN_STATUS="$(sed -n 's/^status=\([^ ]*\).*/\1/p' "$RUN/lease-before.log")"
      OPENED_GENERATION="$(cat "$RUN/lease.generation")"
      APPLY_RESOURCE_COUNT=61
      CLOSE_RESULT="$(tail -n 1 "$RUN/close.log")"
      ;;
    verify)
      for file in canon-timestamp canon-checksum canon-sha contracts; do
        [ -s "$RUN/$file.log" ] || die "$file.log missing or empty"
      done
      ;;
    *) die "unsupported recording kind: $RECORDING_KIND" ;;
  esac
  phase_ok
}
inspect_artifact() {
  local size duration frame_info frames frame_rate minimum_frames floor grep_rc
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

  while IFS= read -r pattern; do
    grep -qE "$pattern" "$RUN/demo.txt" || \
      die "demo.txt missing required $RECORDING_KIND output: $pattern"
  done < <(demo_required_output_patterns "$RECORDING_KIND")

  local_user=$(id -un)
  local_host=$(hostname -s 2>/dev/null || hostname)
  set +e
  grep -qE '/Users/|/home/|AKIA|@' "$RUN/demo.txt"
  grep_rc=$?
  set -e
  if [ "$grep_rc" -eq 0 ]; then
    die "demo.txt contains environment-specific text (path/access-key/email pattern); not publishing"
  elif [ "$grep_rc" -ne 1 ]; then
    die "grep failed on demo.txt"
  fi
  set +e
  grep -oE '[0-9]{12}' "$RUN/demo.txt" | grep -vq 000000000000
  grep_rc=("${PIPESTATUS[@]}")
  set -e
  if [ "${grep_rc[0]}" -gt 1 ] || [ "${grep_rc[1]}" -gt 1 ]; then
    die "grep failed on demo.txt"
  elif [ "${grep_rc[1]}" -eq 0 ]; then
    die "demo.txt contains environment-specific text (12-digit account number); not publishing"
  fi
  set +e
  grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$RUN/demo.txt" | \
    grep -vqE '^203\.0\.113\.|^127\.0\.0\.1$|^10\.|^0\.0\.0\.0$'
  grep_rc=("${PIPESTATUS[@]}")
  set -e
  if [ "${grep_rc[0]}" -gt 1 ] || [ "${grep_rc[1]}" -gt 1 ]; then
    die "grep failed on demo.txt"
  elif [ "${grep_rc[1]}" -eq 0 ]; then
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
  local canonicalizer_sha contract_suite_fixtures fixture fixture_name
  phase_begin build_manifest
  sha=$(shasum -a 256 "$RUN/demo.gif" | awk '{print $1}')

  case "$RECORDING_KIND" in
    lifecycle)
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
      {
        printf 'recorded_from=%s\n' "$recorded_from"
        printf 'recorded_on=%s\n' "$recorded_on"
        printf 'generator_commit=%s (the tree at this commit holds the active recording generator closure)\n' "$GENERATOR_COMMIT"
        printf 'recorder=%s\n' "$recorder"
        # shellcheck disable=SC2016
        printf 'command=`OPERATOR_CIDR=%s make demo` from the repository root\n' "$OPERATOR_CIDR"
        printf 'environment=ENV_ID=demo, TARGET=localstack, workspace default, CLI config empty, operator CIDR %s (TEST-NET-3, /24 to /32)\n' "$OPERATOR_CIDR"
        # shellcheck disable=SC2016
        printf 'plan_apply_destroy=`%s`; `%s`; `%s`\n' "$plan_line" "$apply_line" "$destroy_line"
        printf 'artifact=%s bytes, %s s, %s frames\n' "$GIF_SIZE" "$GIF_DURATION" "$GIF_FRAMES"
        printf 'artifact_sha256=%s\n' "$sha"
      } > "$RUN/provenance.env"
      ;;
    lease)
      terraform_version=$(sed -n '4p' "$RUN/versions.txt" | sed -E 's/^[^0-9]*//')
      localstack_version=$(sed -n '5p' "$RUN/versions.txt")
      recorded_from="LocalStack $localstack_version, Terraform $terraform_version"
      {
        printf 'recorded_from=%s\n' "$recorded_from"
        printf 'generator_commit=%s (the tree at this commit holds the active recording generator closure)\n' "$GENERATOR_COMMIT"
        printf 'environment=ENV_ID=%s, TARGET=localstack, workspace default, CLI config empty, operator CIDR %s (TEST-NET-3, /24 to /32)\n' "$ENV_ID" "$OPERATOR_CIDR"
        printf 'pre_open_status=%s\n' "$PRE_OPEN_STATUS"
        printf 'opened_generation=%s\n' "$OPENED_GENERATION"
        printf 'apply_resource_count=%s\n' "$APPLY_RESOURCE_COUNT"
        printf 'close_result=%s\n' "$CLOSE_RESULT"
        printf 'final_status=%s\n' "$FINAL_STATUS"
        printf 'versions_remaining=%s\n' "$VERSIONS_REMAINING"
        printf 'artifact_sha256=%s\n' "$sha"
        printf 'artifact_size=%s bytes\n' "$GIF_SIZE"
        printf 'artifact_duration=%s s\n' "$GIF_DURATION"
        printf 'artifact_frames=%s\n' "$GIF_FRAMES"
      } > "$RUN/provenance.env"
      ;;
    verify)
      canonicalizer_sha=$(shasum -a 256 scripts/sbom-canon.sh | awk '{print $1}')
      contract_suite_fixtures=
      while IFS= read -r fixture; do
        [ -f "$fixture" ] || die "SBOM contract fixture set is empty"
        fixture_name=${fixture##*/}
        contract_suite_fixtures="${contract_suite_fixtures:+$contract_suite_fixtures, }$fixture_name"
      done < <(printf '%s\n' tests/fixtures/sbom/*.spdx.json | LC_ALL=C sort)
      grep -Fxq 'identical=0' "$RUN/canon-timestamp.log" || \
        die "timestamp canonicalization result is not identical"
      grep -Fxq 'identical=1' "$RUN/canon-checksum.log" || \
        die "checksum canonicalization result is not different"
      grep -Fxq 'PASS: SBOM canonicalization contracts (14 assertions)' \
        "$RUN/contracts.log" || die "SBOM contract result is missing"
      {
        printf 'recorded_from=demo/demo-supplychain.tape\n'
        printf 'generator_commit=%s (the tree at this commit holds the active recording generator closure)\n' "$GENERATOR_COMMIT"
        printf 'canonicalizer_sha256=%s\n' "$canonicalizer_sha"
        printf 'comparison_fixtures_used=base.spdx.json, timestamp-only-difference.spdx.json, same-inventory-different-checksum.spdx.json\n'
        printf 'contract_suite_fixtures_used=%s\n' "$contract_suite_fixtures"
        printf 'timestamp_result=PASS\n'
        printf 'checksum_result=PASS\n'
        printf 'contracts_result=PASS\n'
        printf 'artifact_sha256=%s\n' "$sha"
        printf 'artifact_size=%s bytes\n' "$GIF_SIZE"
        printf 'artifact_duration=%s s\n' "$GIF_DURATION"
        printf 'artifact_frames=%s\n' "$GIF_FRAMES"
      } > "$RUN/provenance.env"
      ;;
    *) die "unsupported recording kind: $RECORDING_KIND" ;;
  esac
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

recheck_generator() {
  phase_begin generator_recheck
  generator_clean_check . "$GENERATOR_COMMIT" || \
    die "generator inputs changed during the recording; not publishing"
  phase_ok
}

render_provenance() {
  phase_begin render_provenance
  cp "$DEMO_TEMPLATE" "$RUN/DEMO_PROVENANCE.md" || \
    die "could not copy provenance template"
  case "$RECORDING_KIND" in
    lifecycle)
      rewrite_provenance_row recorded_from recorded_from
      rewrite_provenance_row recorded_on recorded_on
      rewrite_provenance_row generator_commit 'generator commit'
      rewrite_provenance_row recorder recorder
      rewrite_provenance_row command command
      rewrite_provenance_row environment environment
      rewrite_provenance_row plan_apply_destroy 'plan / apply / destroy'
      rewrite_provenance_row artifact artifact
      rewrite_provenance_row artifact_sha256 'artifact sha256'
      ;;
    lease)
      rewrite_provenance_row recorded_from recorded_from
      rewrite_provenance_row generator_commit 'generator commit'
      rewrite_provenance_row environment environment
      rewrite_provenance_row pre_open_status 'pre-open lease status'
      rewrite_provenance_row opened_generation 'opened generation'
      rewrite_provenance_row apply_resource_count 'apply resource count'
      rewrite_provenance_row close_result 'close result'
      rewrite_provenance_row final_status 'final lease status'
      rewrite_provenance_row versions_remaining 'state and lock versions remaining'
      rewrite_provenance_row artifact_sha256 'gif sha256'
      rewrite_provenance_row artifact_size size
      rewrite_provenance_row artifact_duration duration
      rewrite_provenance_row artifact_frames frames
      ;;
    verify)
      rewrite_provenance_row recorded_from recorded_from
      rewrite_provenance_row generator_commit 'generator commit'
      rewrite_provenance_row canonicalizer_sha256 'canonicalizer sha256'
      rewrite_provenance_row comparison_fixtures_used 'comparison fixtures used'
      rewrite_provenance_row contract_suite_fixtures_used 'contract suite fixtures used'
      rewrite_provenance_row timestamp_result 'timestamp-variant result'
      rewrite_provenance_row checksum_result 'checksum-variant result'
      rewrite_provenance_row contracts_result 'contracts result'
      rewrite_provenance_row artifact_sha256 'gif sha256'
      rewrite_provenance_row artifact_size size
      rewrite_provenance_row artifact_duration duration
      rewrite_provenance_row artifact_frames frames
      ;;
    *) die "unsupported recording kind: $RECORDING_KIND" ;;
  esac
  phase_ok
}
teardown() {
  local rc left lease lease_rc lease_owner lease_generation lease_status
  local owned_generation lease_error
  if [ "${TEARDOWN_RC+x}" = x ]; then
    return "$TEARDOWN_RC"
  fi
  phase_begin teardown
  rc=0
  case "$RECORDING_KIND" in
    lifecycle)
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
      ;;
    lease)
      if [ "${FINAL_STATUS:-}" = closed ]; then
        : > "$RUN/cleanup.log"
      else
        lease_error="$RUN/cleanup-lease.err"
        set +e
        lease="$(scripts/lease.sh get "$ENV_ID" 2> "$lease_error")"
        lease_rc=$?
        set -e
        if [ "$lease_rc" -eq 1 ] && \
           grep -Fxq "lease.sh: no lease for $ENV_ID" "$lease_error"; then
          : > "$RUN/cleanup.log"
        elif [ "$lease_rc" -ne 0 ]; then
          echo "demo: could not read lease during recovery" >&2
          rc=1
        else
          lease_owner="$(jq -r 'if (.owner | type) == "string" then .owner else "" end' <<< "$lease")"
          lease_generation="$(jq -r '.generation // empty' <<< "$lease")"
          lease_status="$(jq -r '.status // empty' <<< "$lease")"
          if [ -s "$RUN/lease.generation" ]; then
            owned_generation="$(cat "$RUN/lease.generation")"
          elif [ "$lease_owner" = "$DEMO_OWNER" ] && [ "$lease_status" = open ] && \
               [[ "$lease_generation" =~ ^[1-9][0-9]*$ ]]; then
            owned_generation=$lease_generation
          else
            owned_generation=
          fi
          if [ "$lease_owner" != "$DEMO_OWNER" ] || \
             [ -z "$owned_generation" ] || \
             [ "$lease_generation" != "$owned_generation" ]; then
            echo "demo: lease belongs to another run" >&2
            rc=1
          elif [ "$lease_status" = closed ]; then
            : > "$RUN/cleanup.log"
          elif ! scripts/lease-sweep-until-closed.sh "$ENV_ID" \
              --owner "$DEMO_OWNER" --generation "$owned_generation" \
              > "$RUN/cleanup.log" 2>&1; then
            cat "$RUN/cleanup.log" >&2
            echo "demo: lease recovery failed (see $RUN/cleanup.log)" >&2
            rc=1
          else
            lease="$(scripts/lease.sh get "$ENV_ID")" || rc=1
            if [ "$rc" -eq 0 ] && \
               ! jq -e --arg owner "$DEMO_OWNER" \
                 --argjson generation "$owned_generation" '
                   .status == "closed"
                   and .owner == $owner
                   and .generation == $generation
                 ' <<< "$lease" >/dev/null; then
              echo "demo: lease recovery did not reach closed" >&2
              rc=1
            fi
          fi
        fi
      fi
      ;;
    verify)
      : > "$RUN/cleanup.log"
      ;;
    *)
      echo "demo: unsupported recording kind during teardown" >&2
      rc=1
      ;;
  esac
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
  recheck_generator
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
