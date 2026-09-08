#!/usr/bin/env bash
unset CDPATH
set -euo pipefail

case "$0" in
  */*) script_dir=${0%/*} ;;
  *) script_dir=. ;;
esac
cd -- "$script_dir/.."
[ -f demo/lib.sh ] || { echo "demo: demo/lib.sh is required" >&2; exit 1; }
# shellcheck source=demo/lib.sh
source demo/lib.sh

DEMO_NAME=${DEMO_NAME:-demo}
config="$(demo_recording_config "$DEMO_NAME")" || exit $?
config_env_id=
while IFS='=' read -r key value; do
  case "$key" in
    ENV_ID) config_env_id=$value ;;
  esac
done <<< "$config"

if [ "$#" -eq 0 ]; then
  set -- bash demo/record.sh
elif [ "$#" -ne 1 ] || [ "$1" != env ]; then
  echo 'demo/env.sh: only "env" is accepted as an argument' >&2
  exit 1
fi

first_makeflag=${MAKEFLAGS-}
first_makeflag=${first_makeflag%%[[:space:]]*}
if [[ "$first_makeflag" =~ ^-?[[:alpha:]]*[ikntq][[:alpha:]]*$ ]]; then
  echo "demo: refusing MAKEFLAGS='${MAKEFLAGS:-}' (-i/-k/-n/-t/-q); run make demo directly" >&2
  exit 1
fi

env_args=()
for name in $DEMO_ENV_PASSTHROUGH; do
  if [ "${!name+x}" = x ]; then
    env_args+=("$name=${!name}")
  fi
done
for assignment in $DEMO_ENV_FIXED; do
  env_args+=("$assignment")
done
if [ -n "$config_env_id" ]; then
  env_args+=("ENV_ID=$config_env_id" "PREVIEW_ROOT=.preview-runs/$config_env_id")
fi

exec env -i "${env_args[@]}" "$@"
