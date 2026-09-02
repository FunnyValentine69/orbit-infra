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
terraform -chdir=bootstrap import aws_kms_alias.signing alias/orbit-infra-79s5rw-signing
terraform -chdir=bootstrap import aws_iam_openid_connect_provider.github[0] <oidc-provider-arn>
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
Phase 3). Local applies use the Makefile's lookup.

## Credential rotation

The Infracost service-account token expires one year after creation
(created 2026-09-02), and the LocalStack student license renews yearly
(2027-09-02). Rotate via `gh secret set INFRACOST_API_KEY` /
`gh secret set LOCALSTACK_AUTH_TOKEN` (hidden prompts).
