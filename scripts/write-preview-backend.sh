#!/usr/bin/env bash
# Render the preview backend config from bootstrap's var.name/var.region
# defaults and the state-bucket naming contract in bootstrap/state.tf.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VARIABLES_FILE="$REPO_ROOT/bootstrap/variables.tf"
BACKEND_HCL_OUT="${BACKEND_HCL_OUT:-$REPO_ROOT/envs/preview/backend.aws.hcl}"

variable_default() {
  local variable_name="$1"
  awk -v variable_name="$variable_name" '
    $1 == "variable" && $2 == "\"" variable_name "\"" { in_variable = 1; next }
    in_variable && $1 == "default" && $2 == "=" {
      value = $0
      sub(/^[^"]*"/, "", value)
      sub(/".*$/, "", value)
      print value
      exit
    }
    in_variable && /^}/ { exit }
  ' "$VARIABLES_FILE"
}

bootstrap_name="$(variable_default name)"
bootstrap_region="$(variable_default region)"

if [[ ! "$bootstrap_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "write-preview-backend.sh: could not derive a safe bootstrap var.name default" >&2
  exit 1
fi
if [[ ! "$bootstrap_region" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "write-preview-backend.sh: could not derive a safe bootstrap var.region default" >&2
  exit 1
fi

tmp_file="$(mktemp "${BACKEND_HCL_OUT}.tmp.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT
printf 'bucket       = "%s-tfstate"\nregion       = "%s"\nuse_lockfile = true\nencrypt      = true\n' \
  "$bootstrap_name" "$bootstrap_region" > "$tmp_file"
mv "$tmp_file" "$BACKEND_HCL_OUT"
trap - EXIT
