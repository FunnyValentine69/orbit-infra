# Runbooks

## Local credentials

The AWS Free Plan has no IAM Identity Center, so local bootstrap uses IAM
user `orbit-bootstrap` (AdministratorAccess, MFA required) with access
keys held only in `~/.aws/credentials` under profile `orbit`, created via
`aws configure --profile orbit`. Deactivate the access key in the IAM
console after bootstrap finishes and re-enable it per session when
needed. CI never uses this key — it authenticates via OIDC only.

## Bootstrap recovery

If local Terraform state is lost before the first `-migrate-state` (i.e.
before `backend.tf` exists), re-import each resource by address using the
names in `bootstrap/`:

```
terraform -chdir=bootstrap import aws_s3_bucket.state orbit-infra-79s5rw-tfstate
terraform -chdir=bootstrap import aws_iam_role.plan_reader orbit-infra-79s5rw-plan-reader
terraform -chdir=bootstrap import aws_iam_role.deployer orbit-infra-79s5rw-deployer
terraform -chdir=bootstrap import aws_iam_role.publisher orbit-infra-79s5rw-publisher
terraform -chdir=bootstrap import 'aws_ecr_repository.repos["placeholder"]' orbit-infra-79s5rw/placeholder
terraform -chdir=bootstrap import 'aws_ecr_repository.repos["orbit-api"]' orbit-infra-79s5rw/orbit-api
terraform -chdir=bootstrap import 'aws_ecr_repository.repos["orbit-worker"]' orbit-infra-79s5rw/orbit-worker
terraform -chdir=bootstrap import 'aws_ecr_repository.repos["orbit-clickhouse"]' orbit-infra-79s5rw/orbit-clickhouse
terraform -chdir=bootstrap import 'aws_ecr_repository.repos["mirror/clickhouse"]' orbit-infra-79s5rw/mirror/clickhouse
terraform -chdir=bootstrap import 'aws_ecr_repository.repos["mirror/redis"]' orbit-infra-79s5rw/mirror/redis
# Find <key-id> via: aws kms describe-key --key-id alias/orbit-infra-79s5rw-signing --query KeyMetadata.KeyId --output text
terraform -chdir=bootstrap import aws_kms_key.signing <key-id>
terraform -chdir=bootstrap import aws_kms_alias.signing alias/orbit-infra-79s5rw-signing
terraform -chdir=bootstrap import 'aws_iam_openid_connect_provider.github[0]' <oidc-provider-arn>
terraform -chdir=bootstrap import 'aws_budgets_budget.monthly[0]' <account-id>:orbit-infra-79s5rw-monthly
```

`<account-id>` is a placeholder — substitute the real 12-digit account ID
locally at import time; never paste it into a tracked file.

If the state bucket object itself is lost or corrupted after migration,
restore a prior version instead of re-importing everything:

```
aws s3api list-object-versions --bucket orbit-infra-79s5rw-tfstate --prefix bootstrap/terraform.tfstate
aws s3api copy-object --bucket orbit-infra-79s5rw-tfstate --copy-source "orbit-infra-79s5rw-tfstate/bootstrap/terraform.tfstate?versionId=<version-id>" --key bootstrap/terraform.tfstate
```

## Operator CIDR change

The ALB allowlist is the repository secret `OPERATOR_CIDR`. To update it:

```
gh secret set OPERATOR_CIDR -R FunnyValentine69/orbit-infra --body "$(curl -s https://checkip.amazonaws.com)/32"
```

Then re-dispatch `session-apply` for each live environment (arrives in
Phase 3). Local applies use the Makefile's lookup; run
`make apply TARGET=aws ENV_ID=<id>` to re-apply the ALB security group
for a specific environment.

## Stuck-environment force-destroy

Every preview environment has a durable lease at `leases/<env_id>.json`
in the state bucket (ADR 0006), states `open -> closing -> closed |
cleanup_failed`. `scripts/lease.sh` manages it directly;
`scripts/close-env.sh` (wired into `make close` and `session-destroy.yml`)
drives it through stage 1 of close.

Check the current state first:

```
make lease-get ENV_ID=<id>
# or: scripts/lease.sh get <id>
```

**Lease is `cleanup_failed`** (a destroy step failed and state was kept
for retry): re-run close, which resumes from `closing`:

```
make close TARGET=aws ENV_ID=<id>
```

**Lease is `closing`** but stalled (task definitions still pending
deletion, or the job was interrupted mid-close): re-run `make close`
again -- it detects `closing` and resumes stage 1 rather than failing on
the CAS precondition. Stage 2 (the sweeper, Phase 5) finishes the
transition to `closed` once every task definition it recorded in the
manifest is confirmed gone.

**Lease is `open` but no resources exist** (e.g. a plan-only dry run, or
resources were removed out-of-band): transition it manually so a future
`open` isn't blocked:

```
scripts/lease.sh transition <id> open closing
scripts/lease.sh transition <id> closing closed
```

**Manual, targeted recovery** when the automated close can't proceed
(e.g. a resource type close-env.sh doesn't know how to retry): inspect
the manifest it already wrote (`state_resources`, `task_definition_arns`,
`tagging_inventory`) via `scripts/lease.sh get <id> | jq .manifest`, clear
the offending resource by hand, then re-run `make close`.

On LocalStack, `DeleteTaskDefinitions` is unsupported
(`scripts/close-env.sh` detects this, notes it in the summary, and leaves
the lease `closing` rather than failing) -- this is expected in local
development and is not itself a stuck-environment condition.

## Credential rotation

CI reads only `LOCALSTACK_AUTH_TOKEN` and `INFRACOST_API_KEY` (both
repository secrets, consumed by terraform-plan.yml); no AWS credentials
are read by any workflow.

The Infracost service-account token expires one year after creation
(created 2026-09-02), and the LocalStack student license renews yearly
(2027-09-02). Rotate via `gh secret set INFRACOST_API_KEY` /
`gh secret set LOCALSTACK_AUTH_TOKEN` (hidden prompts).
