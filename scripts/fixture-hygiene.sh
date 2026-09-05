#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "fixture hygiene failed for $fixture: $*" >&2
  exit 1
}

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <terraform-plan.json>" >&2
  exit 2
fi

fixture="$1"
[ -f "$fixture" ] || fail "file not found"

if ! jq empty "$fixture" >/dev/null 2>&1; then
  fail "invalid JSON"
fi

if jq -e 'has("prior_state")' "$fixture" >/dev/null; then
  fail "top-level prior_state is present"
fi

if jq -e '[.. | objects | to_entries[] | select(.key | test("_sensitive$")) | .value] | flatten | any(. == true)' "$fixture" >/dev/null; then
  fail "a *_sensitive value is true"
fi

while IFS= read -r account_id; do
  if [ "$account_id" != "000000000000" ]; then
    fail "contains a non-placeholder 12-digit number"
  fi
done < <(LC_ALL=C grep -Eo '[0-9]{12}' "$fixture" || true)

while IFS= read -r literal; do
  address="${literal%%/*}"
  IFS=. read -r first second third fourth <<< "$address"
  if [ "$first" -gt 255 ] || [ "$second" -gt 255 ] || [ "$third" -gt 255 ] || [ "$fourth" -gt 255 ]; then
    continue
  fi

  case "$literal" in
    0.0.0.0/0|127.0.0.1)
      ;;
    10.*|192.168.*)
      ;;
    172.*)
      if [ "$second" -lt 16 ] || [ "$second" -gt 31 ]; then
        fail "contains non-private IPv4 literal $literal"
      fi
      ;;
    *)
      fail "contains non-private IPv4 literal $literal"
      ;;
  esac
done < <(LC_ALL=C grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$fixture" || true)

if LC_ALL=C grep -Eiq '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' "$fixture"; then
  fail "contains an email address"
fi
