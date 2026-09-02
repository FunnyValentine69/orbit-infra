# bootstrap/preflight.sh

Read-only AWS ownership discovery, run before P0-6 bootstrap Terraform
creates any dedicated resource.

Classifications: **created** (absent, safe to create) / **external OIDC**
(GitHub OIDC provider already exists and is valid, referenced as a data
source) / **unknown-blocks** (a dedicated resource name already exists;
confirm ownership before bootstrap, then import or rename).

Run: `bootstrap/preflight.sh` (live, needs AWS SSO login),
`bootstrap/preflight.sh --dry-run` (prints planned aws calls, no network),
`bootstrap/preflight.sh --help`. Exit codes: 0 clean, 2 blocked, 3 no creds.

The project suffix (SUFFIX/NAME) is recorded in the local CLAUDE.md.
