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

python3 - "$fixture" <<'PY'
import ipaddress
import json
import re
import sys


fixture = sys.argv[1]
ipv4_candidate_pattern = re.compile(
    r"(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/[0-9]{1,2})?(?![0-9.])"
)
ipv6_candidate_pattern = re.compile(
    r"(?<![0-9A-Fa-f:.])(?=[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*:)"
    r"[0-9A-Fa-f:.]+(?:/[0-9]{1,3})?(?![0-9A-Fa-f:.])"
)
allowed_ipv4_networks = (
    ipaddress.IPv4Network("127.0.0.0/8"),
    ipaddress.IPv4Network("10.0.0.0/8"),
    ipaddress.IPv4Network("172.16.0.0/12"),
    ipaddress.IPv4Network("192.168.0.0/16"),
    ipaddress.IPv4Network("192.0.2.0/24"),
    ipaddress.IPv4Network("198.51.100.0/24"),
    ipaddress.IPv4Network("203.0.113.0/24"),
)
allowed_ipv6_networks = (
    ipaddress.IPv6Network("fc00::/7"),
    ipaddress.IPv6Network("fe80::/10"),
    ipaddress.IPv6Network("2001:db8::/32"),
)
world_open = ipaddress.IPv6Network("::/0")


def ipv4_allowed(candidate, network):
    return candidate == "0.0.0.0/0" or any(
        network.subnet_of(parent) for parent in allowed_ipv4_networks
    )


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
    for candidate in ipv4_candidate_pattern.findall(string):
        try:
            network = ipaddress.ip_network(candidate, strict=False)
        except ValueError:
            continue
        if not isinstance(network, ipaddress.IPv4Network):
            continue
        if not ipv4_allowed(candidate, network):
            print(
                f"fixture hygiene failed for {fixture}: "
                f"contains non-private IPv4 literal {candidate}",
                file=sys.stderr,
            )
            raise SystemExit(1)

    for candidate in ipv6_candidate_pattern.findall(string):
        try:
            network = ipaddress.ip_network(candidate, strict=False)
        except ValueError:
            continue
        if not isinstance(network, ipaddress.IPv6Network):
            continue
        mapped_address = network.network_address.ipv4_mapped
        if mapped_address is not None and network.prefixlen >= 96:
            mapped_network = ipaddress.IPv4Network(
                (mapped_address, network.prefixlen - 96), strict=False
            )
            allowed = ipv4_allowed(
                candidate.split(":")[-1], mapped_network
            )
        else:
            allowed = (
                network == world_open
                or network.is_loopback
                or network.is_unspecified
                or any(network.subnet_of(parent) for parent in allowed_ipv6_networks)
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
