#!/usr/bin/env bash
set -euo pipefail

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks missing; install via brew (tools.lock)"
  exit 1
fi

if ! gitleaks git --no-banner --redact .; then
  exit 1
fi

offending="$(git ls-files | grep -E '(init-clickhouse\.sql|^upstream/|\.upstream-context/|terraform\.tfstate|\.tfvars$|^CLAUDE\.md$|\.env$)' || true)"
if [ -n "$offending" ]; then
  echo "$offending"
  exit 1
fi

# Fail on any tracked file containing an email-shaped token, other than
# the sanctioned local-only placeholders (none@localhost, REPLACE_LOCALLY).
email_offenders=""
while IFS= read -r -d '' f; do
  matches="$(grep -o -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}' "$f" 2>/dev/null | grep -v -E '^(none@localhost)$' || true)"
  if [ -n "$matches" ]; then
    email_offenders="$email_offenders$f: $(echo "$matches" | tr '\n' ' ')
"
  fi
done < <(git ls-files -z)

if [ -n "$email_offenders" ]; then
  echo "email-shaped token found in tracked file(s):"
  printf '%s' "$email_offenders"
  exit 1
fi

echo "pre-push guard: OK"
