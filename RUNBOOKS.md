# Runbooks

Evidence: LOCALSTACK-VERIFIED for apply/close on LocalStack; every real-AWS behavior in this document is CODE-ONLY until the promotion gate P0-3d runs.

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

Then re-dispatch `session-apply` for each live environment. Local applies use
the Makefile's lookup; run
`make apply TARGET=aws ENV_ID=<id>` to re-apply the whole preview
environment for that ID — only the ALB security-group ingress rule
actually changes, since it's the only resource that reads
`var.operator_cidr`.

## Session acceptance

At dispatch time, `session-apply.yml` requires `mode=upstream` or `mode=public`.
`upstream` reads the API and ClickHouse digests from `upstream.lock` and the
Redis digest from `mirror-images.lock`; `public` reads the placeholder, Redis,
and ClickHouse digests from `mirror-images.lock`. It combines the selected set
with the current account's private ECR registry. A missing digest, a tag rather
than a digest, or a repository name that differs from `bootstrap/ecr.tf` fails
before the lease is opened. Before opening the lease, the workflow also
verifies every selected signature through the exported KMS public key and
requires attestations whose predicates match the corresponding lock entries.
The mode and all three resolved image references are stored in the lease
manifest; AWS close reuses those exact references for Terraform destroy and
fails closed if any are missing.

After apply, the workflow runs `aws ecs wait services-stable`, describes every
enabled service, and requires one completed deployment per service whose task
definition ARN exactly matches the corresponding Terraform output.

The hosted runner is deliberately outside `operator_cidr`, so it cannot run a
positive `/health` or `/s3-roundtrip` request. It instead proves the negative
case by accepting only connection-refused or timeout curl exit codes; any HTTP
response fails the job. The job summary prints the ALB URL. From a network
inside `operator_cidr`, the operator completes the positive checks with:

```
curl -fsS "$ALB_URL/health"
curl -fsS "$ALB_URL/s3-roundtrip"
```

## LocalStack CI mode

Dispatch the owner-only, non-scheduled LocalStack lane from `main`:

```
gh workflow run session-apply.yml -f env_id=p4ci -f target=localstack -f mode=public
```

The job starts the pinned LocalStack image, exports the repository's LocalStack
AWS contract (localhost endpoint, test credentials, `us-east-1`, metadata
disabled, and no `AWS_PROFILE`), and runs `make bootstrap-apply
TARGET=localstack` on the fresh runner. It registers QEMU and Buildx because
the task definitions request ARM64 while GitHub's Linux runner is amd64, then
runs the unchanged `make placeholder-build`. Public mode uses
`placeholder:local`, `redis:7-alpine`, and
`clickhouse/clickhouse-server:24.3-alpine`; the workflow validates the
applicable lock-file schema but deliberately skips the AWS-only private-ECR
digest and KMS signature/attestation gate.

After opening a generation-bound lease, the same job runs `make apply`, waits
for every enabled ECS service, checks that each service reached its applied
task definition, probes the LocalStack ALB DNS name from the excluded runner
CIDR, records the ALB URL in the summary, and always runs stage-1 close. The
ALB probe exercises LocalStack's endpoint routing and records whether it
returned HTTP or refused/timed out. LocalStack routes ALB DNS through its
shared edge and does not document source-CIDR enforcement, so this probe does
not prove the real-AWS security-group boundary; only the AWS path treats an
HTTP response from the excluded runner as a failure.

This mode proves the workflow's full bootstrap → lease → apply → service
acceptance → close control flow on one runner. It does not prove GitHub OIDC,
real-AWS IAM, private ECR/KMS supply-chain verification, AWS Budgets, ECS Exec,
real security-group packet enforcement, or a cross-job destroy. A
`session-destroy.yml` dispatch with `target=localstack` is refused because a
fresh runner cannot recover the prior emulator or local state. LocalStack CI
uses licensed credits, so this lane is dispatch-only and must never be added to
a schedule.

## Stuck-environment force-destroy

Every preview environment has a durable lease at `leases/<env_id>.json`
in the state bucket (ADR 0006), states `open -> closing -> closed |
cleanup_failed`. `scripts/lease.sh` manages it directly;
`scripts/close-env.sh` (wired into `make close` and `session-destroy.yml`)
drives it through stage 1 of close. Stage 1 discovers and scales every ECS
service, merges a retry-safe manifest, destroys Terraform resources, requests
asynchronous task-definition deletion, unions state/manifest/ECS/tag candidates,
and verifies each candidate through its exact service API. Results are `gone`,
`pending`, `live`, or `indeterminate`; each five-minute retry iteration is
persisted under `manifest.verification_runs`. Confirmed-gone tag results are
also recorded under `manifest.stale_tag_entries`. A `live` or `indeterminate`
result at the deadline fails stage 1. Stage 1 retains Terraform state and never
sets `closed`; only the Phase 5 sweeper may prune state versions and do that.

GitHub concurrency serializes running jobs for one `env_id`, and `queue: max`
on both session workflows keeps every pending dispatch (up to GitHub's queue
limit) so a queued destroy is not displaced. The lease CAS and generation
checks, not the workflow queue, protect lifecycle state. After overlapping
dispatches, inspect the Actions history; if a destroy did not run,
re-dispatch `session-destroy` for that `env_id`.

Check the current state first:

```
make lease-get TARGET=aws ENV_ID=<id>
# or: TARGET=aws scripts/lease.sh get <id>
```

**Lease is `cleanup_failed`** (a destroy or verification step failed and state
was kept): inspect `cleanup_attempt`, `next_retry_at`,
`manual_intervention_required`, and the last verification summary. Before the
three-attempt limit, re-run close no earlier than `next_retry_at`:

```
make close TARGET=aws ENV_ID=<id>
```

The third failed stage-1 execution leaves `cleanup_failed`, clears
`next_retry_at`, and sets `manual_intervention_required=true`. A fourth
automatic execution is refused. After reviewing and addressing the persisted
`live`/`indeterminate` results, explicitly claim an audited retry:

```
TARGET=aws scripts/close-env.sh --force-retry <id>
```

`--force-retry` increments `cleanup_attempt` and appends to
`cleanup_retry_audit`; it does not delete the retained state or weaken any
resource predicate.

**Lease is `closing`** but stalled (task definitions still pending
deletion, or the job was interrupted mid-close): re-run `make close`
again -- it detects `closing` and resumes stage 1 rather than failing on
the CAS precondition. Stage 2 (the sweeper, Phase 5) finishes the
transition to `closed` once every task definition it recorded in the
manifest is confirmed gone.

**Lease is `open` but no resources exist** (e.g. a plan-only dry run, or
resources were removed out-of-band): move it into stage 1 so the sweeper can
verify the manifest and finish it:

```
TARGET=aws scripts/lease.sh begin-cleanup <id>   # the only entry into closing; counts against the three-attempt budget
```

**Manual, targeted recovery** when the verifier reports `live` or
`indeterminate`: inspect `manifest.candidates`, `manifest.verification_runs`,
`manifest.tag_inventory_observations`, `manifest.stale_tag_entries`, and
`manifest.allowances` via `TARGET=aws scripts/lease.sh get <id> | jq
.manifest`. Resolve only the named resource or access failure, then use the
normal retry or audited force retry above. An unsupported future ARN is one
indeterminate result; it does not discard earlier results.

On LocalStack, the known `DeleteTaskDefinitions` gap is accepted only when the
task definition is already `INACTIVE` and the exact unsupported-operation
signature matches. The allowance ID, ARN, error code, and timestamp are stored
under `manifest.allowances`. The same error on the AWS target fails closed.
Stale tag entries, stale `list-clusters` output, and a VPC endpoint in
`deleted` use normal exact-state predicates and are not allowances.

Every direct lease or close command requires `TARGET`. LocalStack calls also
require an explicit localhost `AWS_ENDPOINT_URL`, test credentials,
`AWS_EC2_METADATA_DISABLED=true`, and an unset `AWS_PROFILE`; prefer the
Makefile targets, which establish that contract. The shared AWS wrapper adds
connect/read limits and a 30-second outer process-group timeout to every cleanup
and lease AWS CLI call except `ecs wait services-stable`, which gets 660 seconds
for the AWS CLI's ten-minute service-stability window.

## Credential rotation

`terraform-plan.yml` reads `LOCALSTACK_AUTH_TOKEN` and `INFRACOST_API_KEY`
and does not assume an AWS role. `mirror-images.yml` and `sign-images.yml`
assume the publisher role; `session-apply.yml` and `session-destroy.yml`
assume the deployer role. These AWS sessions come from GitHub OIDC and use no
stored static AWS access keys.

PR CI secrets are limited to the repository owner's own pull requests; a
compromised owner account is outside the threat model. The workflow grants
`pull-requests: write` only to jobs that post or update their PR comments.

The Infracost service-account token expires one year after creation
(created 2026-09-02), and the LocalStack student license renews yearly
(2027-09-02). Rotate via `gh secret set INFRACOST_API_KEY` /
`gh secret set LOCALSTACK_AUTH_TOKEN` (hidden prompts).
