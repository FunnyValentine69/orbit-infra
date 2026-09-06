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

exec env -i "${env_args[@]}" "$@"
