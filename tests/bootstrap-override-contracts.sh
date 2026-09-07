#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
isolated_repo="$tmp_dir/repo"
mkdir -p "$isolated_repo/bootstrap" "$tmp_dir/bin"
cp "$REPO_ROOT/Makefile" "$isolated_repo/Makefile"
cp "$REPO_ROOT/bootstrap/localstack.backend_override.tf.example" "$isolated_repo/bootstrap/"
override_file="$isolated_repo/bootstrap/backend_override.tf"
terraform_log="$tmp_dir/terraform-calls.log"
trap 'rm -rf -- "$tmp_dir"' EXIT

cat > "$tmp_dir/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_TERRAFORM_CALL_LOG:?}"
case "$*" in
  *" init "*) stage=init ;;
  *" plan "*) stage=plan ;;
  *" apply "*) stage=apply ;;
  *) echo "unexpected terraform call: $*" >&2; exit 20 ;;
esac
if [ "$stage" = "${FAKE_TERRAFORM_FAIL_STAGE:?}" ]; then
  echo "$stage diagnostic" >&2
  exit "${FAKE_TERRAFORM_FAIL_RC:?}"
fi
EOF
chmod +x "$tmp_dir/bin/terraform"

pass_count=0
pass() {
  pass_count=$((pass_count + 1))
  echo "PASS: $1"
}

run_make() {
  PATH="$tmp_dir/bin:$PATH" \
    FAKE_TERRAFORM_CALL_LOG="$terraform_log" \
    FAKE_TERRAFORM_FAIL_STAGE="$1" \
    FAKE_TERRAFORM_FAIL_RC="$2" \
    make -s -C "$isolated_repo" "$3" TARGET=localstack OPERATOR_CIDR=203.0.113.0/24
}

sentinel="$tmp_dir/operator-owned-override.tf"
printf '%s\n' '# sentinel: operator-owned override' > "$sentinel"
for target in bootstrap-plan bootstrap-apply; do
  cp "$sentinel" "$override_file"
  : > "$terraform_log"
  set +e
  output="$(run_make none 41 "$target" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] || \
     ! grep -Fq 'bootstrap/backend_override.tf already exists; refusing to overwrite or remove it' <<< "$output"; then
    echo "$target must refuse an existing backend override: $output" >&2
    exit 1
  fi
  if [ -s "$terraform_log" ] || [ ! -f "$override_file" ] || \
     ! cmp -s "$sentinel" "$override_file"; then
    echo "$target must make zero Terraform calls and preserve the existing override byte-identically" >&2
    exit 1
  fi
  pass "$target existing override refusal"
  rm -f "$override_file"

  dangling_target="../operator-owned-missing-backend.tf"
  ln -s "$dangling_target" "$override_file"
  : > "$terraform_log"
  set +e
  output="$(run_make none 41 "$target" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] || \
     ! grep -Fq 'bootstrap/backend_override.tf already exists; refusing to overwrite or remove it' <<< "$output"; then
    echo "$target must refuse a dangling backend override symlink: $output" >&2
    exit 1
  fi
  if [ -s "$terraform_log" ] || [ -e "$override_file" ] || [ ! -L "$override_file" ] || \
     [ "$(readlink "$override_file")" != "$dangling_target" ]; then
    echo "$target must make zero Terraform calls and preserve the dangling override target" >&2
    exit 1
  fi
  pass "$target dangling override refusal"
  rm -f "$override_file"
done

for target in bootstrap-plan bootstrap-apply; do
  : > "$terraform_log"
  if ! output="$(run_make none 41 "$target" 2>&1)"; then
    echo "$target no-override path failed: $output" >&2
    exit 1
  fi
  if [ -e "$override_file" ] || [ -L "$override_file" ]; then
    echo "$target must remove the override it created after success" >&2
    exit 1
  fi
  expected_second_stage="${target#bootstrap-}"
  if [ "$(wc -l < "$terraform_log" | tr -d ' ')" -ne 2 ] || \
     ! grep -Fq ' init ' "$terraform_log" || \
     ! grep -Fq " $expected_second_stage " "$terraform_log"; then
    echo "$target must invoke Terraform init and $expected_second_stage exactly once" >&2
    exit 1
  fi
  pass "$target no-override cleanup"
done

for target in bootstrap-plan bootstrap-apply; do
  chmod 000 "$isolated_repo/bootstrap/localstack.backend_override.tf.example"
  : > "$terraform_log"
  set +e
  output="$(run_make none 41 "$target" 2>&1)"
  rc=$?
  set -e
  chmod 644 "$isolated_repo/bootstrap/localstack.backend_override.tf.example"
  if [ "$rc" -eq 0 ]; then
    echo "$target must fail when the backend override example cannot be read: $output" >&2
    exit 1
  fi
  if [ -s "$terraform_log" ] || [ -e "$override_file" ] || [ -L "$override_file" ]; then
    echo "$target copy failure must make zero Terraform calls and leave no override" >&2
    exit 1
  fi
  pass "$target copy failure cleanup"
done

for failure_case in \
  'bootstrap-plan|init|41' \
  'bootstrap-plan|plan|42' \
  'bootstrap-apply|init|43' \
  'bootstrap-apply|apply|44'; do
  target="${failure_case%%|*}"
  remainder="${failure_case#*|}"
  stage="${remainder%%|*}"
  failure_rc="${remainder##*|}"
  : > "$terraform_log"
  set +e
  output="$(run_make "$stage" "$failure_rc" "$target" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] || ! grep -Fq "$stage diagnostic" <<< "$output" || \
     ! grep -Fq "Error $failure_rc" <<< "$output"; then
    echo "$target must preserve the $stage failure and its diagnostic: $output" >&2
    exit 1
  fi
  if [ -e "$override_file" ] || [ -L "$override_file" ]; then
    echo "$target must remove only its recipe-created override after $stage failure" >&2
    exit 1
  fi
  pass "$target $stage failure cleanup"
done

echo "PASS: bootstrap override contracts ($pass_count cases)"
