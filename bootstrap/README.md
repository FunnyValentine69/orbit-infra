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

## Apply sequence

1. `bootstrap/preflight.sh` (must exit 0)
2. `terraform -chdir=bootstrap init` (local state)
3. `terraform -chdir=bootstrap plan -var-file=terraform.tfvars`
4. `terraform -chdir=bootstrap apply`
5. Copy `backend.tf.example` to `backend.tf`
6. `terraform -chdir=bootstrap init -migrate-state`
7. Commit `backend.tf`

Never run `terraform destroy` here — every resource has `prevent_destroy`.

## LocalStack target

`make bootstrap-apply TARGET=localstack` (and `bootstrap-plan TARGET=localstack`)
point this root at a local LocalStack instance instead of real AWS. It always
uses the local state file in `bootstrap/` — this target is never migrated to
the S3 backend. `aws_budgets_budget.monthly` is skipped (Budgets is not
emulated by LocalStack). Running `localstack stop` (`make localstack-down`)
discards everything created this way; nothing here is durable.

## After apply

Publish the three role ARNs as GitHub repository variables (not secrets;
the ARNs are not secret but are never committed to this repo), then
dispatch the smoke test:

```
terraform -chdir=bootstrap output -raw plan_reader_role_arn | gh variable set AWS_ROLE_PLAN_READER
terraform -chdir=bootstrap output -raw deployer_role_arn | gh variable set AWS_ROLE_DEPLOYER
terraform -chdir=bootstrap output -raw publisher_role_arn | gh variable set AWS_ROLE_PUBLISHER
gh workflow run oidc-smoke.yml
```
