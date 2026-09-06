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

Real-AWS preview workflows run `scripts/write-preview-backend.sh` before their
Make targets. The script derives `envs/preview/backend.aws.hcl` from bootstrap's
committed `var.name`/`var.region` defaults and the state bucket's
`${var.name}-tfstate` naming contract, so no additional secret is required.

## Apply sequence

1. `cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars` and edit `budget_email` (`terraform.tfvars` is gitignored; verify with `git check-ignore bootstrap/terraform.tfvars`)
2. `rm -f bootstrap/backend_override.tf`
3. `AWS_PROFILE=orbit AWS_REGION=us-east-1 bootstrap/preflight.sh` (must exit 0)
4. `AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap init` (local state)
5. `make bootstrap-plan TARGET=aws` (or `AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap plan -var-file=terraform.tfvars -var target=aws -var region=us-east-1`)
6. `make bootstrap-apply TARGET=aws` (sets `AWS_PROFILE` and `AWS_REGION` for preflight and terraform together)
7. Copy `backend.tf.example` to `backend.tf`
8. `AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap init -migrate-state`
9. Commit `backend.tf`

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

## Task permissions boundary (PR #2 Tier 2)

`bootstrap/roles.tf` creates `aws_iam_policy.task_boundary`, named
`${var.name}-task-boundary` (output `task_boundary_policy_arn`). This is
the maximum permission set the deployer is allowed to attach as a
permissions boundary on any execution/task role it creates via
`modules/ecs-service`; the deployer policy denies `iam:CreateRole`,
`iam:PutRolePolicy`, and `iam:AttachRolePolicy` unless the exact boundary
ARN is set, and denies `iam:DeleteRolePermissionsBoundary` outright.
`envs/preview/main.tf` computes this same ARN from `var.name` plus
`data.aws_caller_identity`/`data.aws_partition` (naming contract only —
it does not read the bootstrap output) and passes it to every
`ecs-service`/`redis`/`clickhouse` module call as
`permissions_boundary_arn`. Mutation actions in the deployer policy are
also conditioned on the `Project` tag (`var.project_tag`, default
`orbit-infra`), matching the authoritative `var.project_tag` merged into
`default_tags.Project` by `envs/preview/main.tf`.

The deployer also has read-only access to pull the project's ECR artifacts and
read the signing key's public half. `session-apply.yml` uses those grants to
verify selected image signatures and attestations before it opens a lease;
only the publisher role can sign or push images.

The generated statement inventory, principal bindings, condition truth tables,
and P0-3d evidence cases are in [`../docs/iam-matrix.md`](../docs/iam-matrix.md).

## After apply

Publish the three role ARNs as GitHub repository secrets (not variables --
role ARNs embed the 12-digit AWS account ID, which GitHub does not mask
in logs for repository variables but does mask for secrets; the ARNs are
never committed to this repo), then dispatch the smoke test:

```
AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap output -raw plan_reader_role_arn | gh secret set AWS_ROLE_PLAN_READER
AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap output -raw deployer_role_arn | gh secret set AWS_ROLE_DEPLOYER
AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap output -raw publisher_role_arn | gh secret set AWS_ROLE_PUBLISHER
AWS_PROFILE=orbit AWS_REGION=us-east-1 terraform -chdir=bootstrap output -raw kms_signing_key_arn | gh secret set AWS_KMS_SIGNING_KEY_ARN
gh workflow run oidc-smoke.yml
```

`AWS_KMS_SIGNING_KEY_ARN` is consumed by `.github/workflows/mirror-images.yml`
and `.github/workflows/sign-images.yml` for KMS signing
(`--tlog-upload=false`, ADR 0007). `session-apply.yml` uses the identifier only
to export the public key before verifying the selected images.

## Gates / size

`bootstrap/policy-size-check.sh` (required by default in `scripts/gates.sh` as
the `policy-size` gate) renders a LocalStack plan of `bootstrap/` and checks
every planned `aws_iam_policy`/`aws_iam_role_policy` document against AWS's
size quotas. Every policy document must be plan-time known: reference other
bootstrap resources' ARNs deterministically (e.g. via `data` sources or
computed strings), not via `.arn` attributes of resources that only become
known after apply. Run it directly with `bootstrap/policy-size-check.sh` (it always renders
against the LocalStack target, no AWS credentials needed), or via
`scripts/gates.sh` alongside the other gates. CI skips it only in the
secret-free all-PR gates job, then runs it explicitly in the owner-only
`plan-localstack` job after the emulator is healthy.
