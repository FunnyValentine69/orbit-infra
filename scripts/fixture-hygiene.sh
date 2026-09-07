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

if jq -e '[.. | objects | to_entries[] | select(.key == "sensitive_values" or (.key | test("_sensitive$"))) | .value | .. | select(. == true)] | any' "$fixture" >/dev/null; then
  fail "a *_sensitive value is true or sensitive_values has a true leaf"
fi

if jq -e '[.. | objects | select(has("sensitive") and .sensitive == true)] | any' "$fixture" >/dev/null; then
  fail 'an object has "sensitive": true'
fi

if jq -e 'has("variables") and (.variables | type == "object" and length > 0)' "$fixture" >/dev/null; then
  fail "variables must not be serialized into fixtures"
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

python3 - "$fixture" <<'PY'
import ipaddress
import json
import re
import sys


fixture = sys.argv[1]
candidate_pattern = re.compile(
    r"(?<![0-9A-Fa-f:])(?=[0-9A-Fa-f:]*:[0-9A-Fa-f:]*:)"
    r"[0-9A-Fa-f:]+(?:/[0-9]{1,3})?(?![0-9A-Fa-f:])"
)
allowed_networks = (
    ipaddress.IPv6Network("fc00::/7"),
    ipaddress.IPv6Network("fe80::/10"),
    ipaddress.IPv6Network("2001:db8::/32"),
)
world_open = ipaddress.IPv6Network("::/0")


def json_strings(value):
    if isinstance(value, dict):
        for key, child in value.items():
            yield key
            yield from json_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from json_strings(child)
    elif isinstance(value, str):
        yield value


with open(fixture, encoding="utf-8") as fixture_file:
    fixture_json = json.load(fixture_file)

for string in json_strings(fixture_json):
    for candidate in candidate_pattern.findall(string):
        try:
            network = ipaddress.ip_network(candidate, strict=False)
        except ValueError:
            continue
        if not isinstance(network, ipaddress.IPv6Network):
            continue
        allowed = (
            network == world_open
            or network.is_loopback
            or network.is_unspecified
            or any(network.subnet_of(parent) for parent in allowed_networks)
        )
        if not allowed:
            print(
                f"fixture hygiene failed for {fixture}: "
                f"contains non-private IPv6 literal {candidate}",
                file=sys.stderr,
            )
            raise SystemExit(1)
PY

if LC_ALL=C grep -Eiq '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' "$fixture"; then
  fail "contains an email address"
fi
