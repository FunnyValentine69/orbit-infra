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

echo "pre-push guard: OK"
