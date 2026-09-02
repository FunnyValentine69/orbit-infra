# bootstrap/preflight.sh

Read-only AWS ownership discovery, run before P0-6 bootstrap Terraform
creates any dedicated resource.

Classifications: **created** (absent, safe to create) / **external OIDC**
(GitHub OIDC provider already exists and is valid, referenced as a data
source) / **unknown-blocks** (a dedicated resource name already exists;
confirm ownership before bootstrap, then import or rename).

Run: `bootstrap/preflight.sh` (live, needs AWS credentials for profile orbit, see RUNBOOKS.md § Local credentials),
`bootstrap/preflight.sh --dry-run` (prints planned aws calls, no network),
`bootstrap/preflight.sh --help`. Exit codes: 0 clean, 2 blocked, 3 no creds.

The project suffix (SUFFIX/NAME) is hardcoded as the default of `var.name` in
bootstrap/variables.tf and `NAME` in bootstrap/preflight.sh (keep them
identical); also noted in the local CLAUDE.md.

The region is set once via the `AWS_REGION` env var (default `us-east-1`,
same default as `AWS_PROFILE=orbit`) — never in `terraform.tfvars`. The
`Makefile` exports `AWS_REGION` to both `bootstrap-preflight` (which reads
it directly) and the `terraform plan`/`apply` targets (passed as
`-var region=$(AWS_REGION)`). Prefer the Make targets, which set both
`AWS_PROFILE` and `AWS_REGION` consistently; every direct `terraform`
invocation below is shown with the equivalent env prefix.

## Apply sequence

1. `rm -f bootstrap/backend_override.tf`
2. `AWS_PROFILE=orbit AWS_REGION=us-east-1 bootstrap/preflight.sh` (must exit 0)
3. `AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap init` (local state)
4. `make bootstrap-plan TARGET=aws` (or `AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap plan -var-file=terraform.tfvars -var target=aws -var region=us-east-1`)
5. `make bootstrap-apply TARGET=aws` (sets `AWS_PROFILE` and `AWS_REGION` for preflight and terraform together)
6. Copy `backend.tf.example` to `backend.tf`
7. `AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap init -migrate-state`
8. Commit `backend.tf`

Terraform auto-loads `terraform.tfvars` from the `-chdir` directory; the
`plan`/`apply` invocations above pass `-var-file` explicitly only to match
what the Make targets do.

Never run `terraform destroy` here — every resource has `prevent_destroy`.

## LocalStack target

`make bootstrap-apply TARGET=localstack` (and `bootstrap-plan TARGET=localstack`)
point this root at a local LocalStack instance instead of real AWS. State
isolation from the real-AWS backend uses Terraform's override-file
mechanism: `bootstrap/localstack.backend_override.tf.example` is copied to
`bootstrap/backend_override.tf` (gitignored), which Terraform loads after
the primary configuration and merges as an override — replacing the
backend block for that run only, without editing `backend.tf` (the S3
backend added post-bootstrap, see below). The override backend is
`local`, writing to `bootstrap/terraform.localstack.tfstate` (gitignored)
under its own `TF_DATA_DIR=.terraform-localstack` (gitignored), so the
LocalStack state, working directory, and provider cache never share
anything with the real-AWS state or `.terraform/`. `make bootstrap-apply
TARGET=aws` removes `bootstrap/backend_override.tf` if present so the
default (real) backend and `TF_DATA_DIR` apply. `aws_budgets_budget.monthly`
is skipped (Budgets is not emulated by LocalStack). Running `localstack
stop` (`make localstack-down`) discards everything created this way;
nothing here is durable.

## After apply

Publish the three role ARNs as GitHub repository secrets (not variables --
role ARNs embed the 12-digit AWS account ID, which GitHub does not mask
in logs for repository variables but does mask for secrets; the ARNs are
never committed to this repo), then dispatch the smoke test:

```
terraform -chdir=bootstrap output -raw plan_reader_role_arn | gh secret set AWS_ROLE_PLAN_READER
terraform -chdir=bootstrap output -raw deployer_role_arn | gh secret set AWS_ROLE_DEPLOYER
terraform -chdir=bootstrap output -raw publisher_role_arn | gh secret set AWS_ROLE_PUBLISHER
gh workflow run oidc-smoke.yml
```
