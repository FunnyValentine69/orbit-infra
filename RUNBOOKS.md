# Runbooks

Evidence: LOCALSTACK-VERIFIED for apply/close on LocalStack; every real-AWS behavior in this document is CODE-ONLY until the promotion gate P0-3d runs. Run every procedure from the repository root.

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

1. Read the replacement CIDR without echoing it, then update the repository
   secret without printing the value:

```
read -r -s -p "OPERATOR_CIDR: " OPERATOR_CIDR
echo
export OPERATOR_CIDR
printf '%s' "$OPERATOR_CIDR" | gh secret set OPERATOR_CIDR
```

2. Bind the active environment and recover its exact digest-pinned image inputs
   from the durable lease. Refuse to continue unless all three are present:

```
ENV_ID=demo1
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
export TF_VAR_api_image="$(jq -er '.manifest.images.api_image' <<< "$LEASE_JSON")"
export TF_VAR_redis_image="$(jq -er '.manifest.images.redis_image' <<< "$LEASE_JSON")"
export TF_VAR_clickhouse_image="$(jq -er '.manifest.images.clickhouse_image' <<< "$LEASE_JSON")"
```

3. Generate the existing backend configuration, create a saved plan, and apply
   that exact plan. The ingress rule is the intended change; inspect the plan
   and stop if it contains any unrelated replacement:

```
scripts/write-preview-backend.sh
make plan TARGET=aws ENV_ID="$ENV_ID" OPERATOR_CIDR="$OPERATOR_CIDR"
make apply TARGET=aws ENV_ID="$ENV_ID" OPERATOR_CIDR="$OPERATOR_CIDR"
```

Executed: CODE-ONLY — promote with `make plan TARGET=aws ENV_ID=cidr1 OPERATOR_CIDR="$OPERATOR_CIDR"` followed by `make apply TARGET=aws ENV_ID=cidr1 OPERATOR_CIDR="$OPERATOR_CIDR"` after the real-AWS promotion gate.

## Start session

1. Choose a valid environment ID, target, and image mode. Use `public` for the
   placeholder stack or `upstream` for the locked upstream workload:

```
ENV_ID=demo1
TARGET=aws
MODE=public
```

2. For `TARGET=aws`, confirm that the durable lease is absent or `closed`.
   An `open`, `closing`, or `cleanup_failed` lease is an intentional refusal,
   not a signal to bypass the state machine. A LocalStack CI run cannot inspect
   another run's lease because its emulator is fresh:

```
make lease-get TARGET=aws ENV_ID="$ENV_ID"
```

3. Dispatch from `main`, then inspect the matching run and wait for its
   terminal conclusion:

```
gh workflow run session-apply.yml --ref main -f env_id="$ENV_ID" -f target="$TARGET" -f mode="$MODE"
gh run list --workflow session-apply.yml --branch main --event workflow_dispatch --limit 5
```

4. For `TARGET=aws`, read the lease and confirm it is `open`, has a string
   workflow-run owner, and already carries the requested target, mode, and all
   three image references. The owner and initial manifest are part of the same
   CAS PUT that created the generation. Use the ALB URL from the run summary
   for the acceptance commands below. For `TARGET=localstack`, the same job
   always performs owner-bound stage-1 close, so its terminal lease is
   `closing` on that job's fresh emulator and is not observable from a later
   runner.

```
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
jq -e '.status == "open" and (.owner | type) == "string"
  and .manifest.target == "aws"
  and (.manifest.mode == "public" or .manifest.mode == "upstream")
  and all(.manifest.images.api_image, .manifest.images.redis_image, .manifest.images.clickhouse_image;
    type == "string" and length > 0)' <<< "$LEASE_JSON"
```

Executed: CODE-ONLY — promote with `gh workflow run session-apply.yml --ref main -f env_id=p4ci -f target=localstack -f mode=public` after this change reaches `main`.

## End session

1. Bind the real-AWS environment and inspect its current lease generation and
   cleanup-attempt budget:

```
ENV_ID=demo1
make lease-get TARGET=aws ENV_ID="$ENV_ID"
```

2. Dispatch the existing stage-1 close workflow from `main` and follow its
   run. Do not dispatch `session-destroy target=localstack`: LocalStack state
   is runner-local and `session-apply` already closes in the same job.

```
gh workflow run session-destroy.yml --ref main -f env_id="$ENV_ID" -f target=aws
gh run list --workflow session-destroy.yml --branch main --event workflow_dispatch --limit 5
```

3. Confirm that a successful stage 1 retained Terraform state evidence and
   left the lease `closing` for the Phase 5 sweeper. `closed` is not a
   stage-1 success state:

```
make lease-get TARGET=aws ENV_ID="$ENV_ID"
```

Executed: LOCALSTACK-VERIFIED 2026-09-03 — the LocalStack close path ran through `make test-concurrency TARGET=localstack OPERATOR_CIDR=10.255.255.255/32` (two generation-bound closes, both leases `closing`, empty states); the independent AWS dispatch is CODE-ONLY until P0-3d.

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
The workflow-run owner, mode, and all three resolved image references are
stored atomically by the lease-open CAS; AWS close reuses those exact
references for Terraform destroy and fails closed if any are missing.
Cancellation and failure cleanup re-read the lease instead of trusting step
outputs and proceed only for an `open` or `closing` lease owned by that run.

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

Reruns by collaborators are refused because the triggering actor is checked.

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

After atomically opening an owner- and generation-bound lease with its initial
manifest, the same job runs `make apply`, waits
for every enabled ECS service, checks that each service reached its applied
task definition, probes the Terraform `api_url` output (the LocalStack ALB) from the excluded runner
CIDR, records the ALB URL in the summary, and always runs stage-1 close. The
ALB probe exercises LocalStack's endpoint routing and records whether it
returned HTTP or refused/timed out. LocalStack routes ALB DNS through its
shared edge and does not document source-CIDR enforcement, so this probe does
not prove the real-AWS security-group boundary; only the AWS path treats an
HTTP response from the excluded runner as a failure.

This mode proves the workflow's full bootstrap → lease → apply → service
acceptance → close control flow on one runner. It does not prove GitHub OIDC,
real-AWS IAM, private ECR/KMS supply-chain verification, AWS Budgets, ECS Exec,
real security-group packet enforcement, or a cross-job destroy. Every
LocalStack CI run uses a fresh runner and fresh emulator, so the gh-driven
dispatch test proves only GitHub concurrency queueing on this target. Lease CAS,
refusal on `open`/`closing`/`cleanup_failed`, and generation increments are
proved locally against one emulator by `tests/localstack-concurrency.sh`. A
`session-destroy.yml` dispatch with `target=localstack` is refused because a
fresh runner cannot recover the prior emulator or local state. LocalStack CI
uses licensed credits, so this lane is dispatch-only and must never be added to
a schedule.

## Stuck-environment force-destroy

1. Bind the environment, read the durable lease once, and inspect only its
   lifecycle fields and most recent exact-resource outcomes. Keep the retained
   Terraform state; it is evidence and an input to every retry:

```
ENV_ID=demo1
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
jq '{status,generation,owner,cleanup_attempt,next_retry_at,manual_intervention_required,initial_target:.manifest.target,initial_mode:.manifest.mode,last_verification:.manifest.verification_runs[-1]}' <<< "$LEASE_JSON"
```

2. If the verifier reports VPC deletion blocked by orphaned ENIs, derive the
   exact VPC from the manifest and inspect a redacted field set. Resolve the
   owning endpoint, load balancer, or ECS service; never delete a
   requester-managed ENI directly:

```
VPC_ID="$(jq -er '.manifest.candidates[] | select(.resource_type == "ec2:vpc") | .id' <<< "$LEASE_JSON" | head -n1)"
TARGET=aws scripts/aws-cli.sh ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[].{id:NetworkInterfaceId,status:Status,requester_managed:RequesterManaged,description:Description}' --output json
```

3. If the exact S3 candidate is still live because the data bucket is not
   empty, resolve its name from the lease, assert that it is this environment's
   data bucket, inspect current keys, and empty only that bucket. Versioning is
   intentionally disabled on the ephemeral data bucket:

```
BUCKET="$(jq -er '.manifest.candidates[] | select(.resource_type == "s3:bucket") | .id' <<< "$LEASE_JSON" | head -n1)"
case "$BUCKET" in *-"$ENV_ID"-data) ;; *) echo "refusing unexpected bucket: $BUCKET" >&2; exit 1 ;; esac
TARGET=aws scripts/aws-cli.sh s3api list-objects-v2 --bucket "$BUCKET" --max-items 20 --query 'Contents[].Key' --output json
TARGET=aws scripts/aws-cli.sh s3 rm "s3://$BUCKET" --recursive
```

4. Before the three-attempt limit, wait until `next_retry_at`, refresh the
   lease, and use the normal retry path. `make close` resumes either `closing`
   or due `cleanup_failed` state:

```
make close TARGET=aws ENV_ID="$ENV_ID" OPERATOR_CIDR="$OPERATOR_CIDR"
```

5. When the third failed execution leaves `cleanup_failed`, retained state,
   `next_retry_at=null`, and `manual_intervention_required=true`, re-read the
   lease generation after the targeted repair and claim one audited force
   retry. Bind both owner and generation from the same read so stale operator
   work cannot touch a newer lease or a generation owned by another run:

```
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
GENERATION="$(jq -er '.generation' <<< "$LEASE_JSON")"
OWNER="$(jq -er '.owner | select(type == "string" and length > 0)' <<< "$LEASE_JSON")"
TARGET=aws scripts/close-env.sh --force-retry --generation "$GENERATION" --owner "$OWNER" "$ENV_ID"
```

6. Confirm `cleanup_attempt` incremented, `cleanup_retry_audit` gained the
   forced attempt, state remains retained, and the lease is either `closing`
   after successful stage 1 or `cleanup_failed` with a new exact error:

```
TARGET=aws scripts/lease.sh get "$ENV_ID" | jq '{status,generation,owner,cleanup_attempt,manual_intervention_required,cleanup_retry_audit,last_verification:.manifest.verification_runs[-1]}'
```

The exact verifier owns all `gone`, `pending`, `live`, and `indeterminate`
predicates. The only LocalStack allowance remains an unsupported
`DeleteTaskDefinitions` response for an already-`INACTIVE` task definition;
its ID, ARN, error code, and timestamp are persisted. Stale tags, retained
cluster-list entries, VPC endpoints in `deleted`, ENI ownership, and S3
emptiness are never generalized allowances.

Executed: LOCALSTACK-VERIFIED 2026-09-03 — an applied `rbstuck` environment whose lease was driven to `cleanup_failed` with cleanup_attempt 3 and manual_intervention_required refused `close-env.sh` with exit 3; the audited step 5 run destroyed all 59 resources and left `closing`, cleanup_attempt 4, one `cleanup_retry_audit` entry (steps 2 and 3 remain CODE-ONLY: no ENI orphan or non-empty bucket occurred). Command used: `TARGET=localstack AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 AWS_EC2_METADATA_DISABLED=true OPERATOR_CIDR=10.255.255.255/32 scripts/close-env.sh --force-retry rbstuck`.

## Rotate secrets

1. Authenticate `gh` for the repository, then rotate each secret through its
   hidden prompt. Never pass values on a command line, echo them, or write them
   to a file:

```
gh secret set LOCALSTACK_AUTH_TOKEN
gh secret set INFRACOST_API_KEY
gh secret set OPERATOR_CIDR
gh secret set AWS_KMS_SIGNING_KEY_ARN
gh secret set AWS_ROLE_PLAN_READER
gh secret set AWS_ROLE_DEPLOYER
gh secret set AWS_ROLE_PUBLISHER
```

2. Confirm only the names and update timestamps, never the values:

```
gh secret list
```

3. Exercise each consumer after rotation: `oidc-smoke` covers all three role
   ARN secrets, a LocalStack session covers `LOCALSTACK_AUTH_TOKEN`, an owner
   PR covers `INFRACOST_API_KEY`, the operator-CIDR procedure covers
   `OPERATOR_CIDR`, and the image workflows cover the publisher role and KMS
   key:

```
gh workflow run oidc-smoke.yml --ref main
gh workflow run session-apply.yml --ref main -f env_id=rot1 -f target=localstack -f mode=public
gh workflow run mirror-images.yml --ref main
```

The Infracost service-account token expires one year after creation (created
2026-09-02), and the LocalStack student license renews yearly (2027-09-02).

Executed: CODE-ONLY — promote the role-secret checks with `gh workflow run oidc-smoke.yml --ref main`; promote the LocalStack token with `gh workflow run session-apply.yml --ref main -f env_id=rot1 -f target=localstack -f mode=public`; verify Infracost only on an owner PR.

## Re-sign an already-signed digest

1. Re-dispatch `sign-images` with the exact commit already locked in
   `upstream.lock`:

```
UPSTREAM_SHA="$(awk '$1 == "upstream_sha:" { print $2 }' upstream.lock)"
gh workflow run sign-images.yml --ref main -f upstream_sha="$UPSTREAM_SHA"
```

2. Re-dispatch `mirror-images` for the placeholder and public-image mirrors:

```
gh workflow run mirror-images.yml --ref main
```

3. Inspect both runs. Each workflow re-runs its scans and final verification.
   An existing valid signature is not duplicated, and an attestation is added
   only when no existing predicate matches the current lock inputs. Existing
   destination images must still match the locked digest; a mismatch fails.

```
gh run list --workflow sign-images.yml --branch main --event workflow_dispatch --limit 3
gh run list --workflow mirror-images.yml --branch main --event workflow_dispatch --limit 3
```

Executed: CODE-ONLY — promote with `gh workflow run sign-images.yml --ref main -f upstream_sha="$(awk '$1 == "upstream_sha:" { print $2 }' upstream.lock)"` and `gh workflow run mirror-images.yml --ref main` after P0-3b.

## Image bump

1. For a Redis or ClickHouse base-image bump, resolve the new ARM64 manifest
   digest, then update the corresponding `*_source` and `*_digest` fields in
   `mirror-images.lock`. Keep the repository fields unchanged. For a
   placeholder source bump, set `placeholder_digest` and
   `placeholder_source_sha` to explicit `<pending ...>` markers for the first
   run, dispatch from `main`, then replace both markers with the digest and
   source commit reported by that run.

2. Mirror, scan, sign, and attest the new locked public-image set, then run it
   a second time to verify the idempotent already-published/already-signed path:

```
gh workflow run mirror-images.yml --ref main
gh workflow run mirror-images.yml --ref main
```

3. A changed ClickHouse mirror digest changes a repository-owned build input
   for the private ClickHouse image. Set the `upstream.lock`
   `repo_build_inputs_sha256` field to an explicit pending marker, run the
   existing archive-only builder without pushing, and record the reported
   `upstream_archive_sha256`, `repo_build_inputs_sha256`, and three `local_id`
   values in `upstream.lock`:

```
UPSTREAM_DIR="${UPSTREAM_DIR:?set UPSTREAM_DIR to the clean locked clone}"
PUSH=0 UPSTREAM_DIR="$UPSTREAM_DIR" scripts/build-upstream.sh
```

4. For an upstream commit bump, update `upstream_sha` first and perform the
   same no-push build-and-record step. The builder verifies origin, exact HEAD,
   clean working tree, archive hash, and repository-owned input hash before it
   builds.

5. After the real-AWS bootstrap and registry login are ready, push the three
   exact builds. `PUSH=1` records the exact destination-repository digests back
   into `upstream.lock`; then dispatch the idempotent signing workflow:

```
ECR_REGISTRY="${ECR_REGISTRY:?set the private ECR registry without printing it}"
PUSH=1 UPSTREAM_DIR="$UPSTREAM_DIR" ECR_REGISTRY="$ECR_REGISTRY" scripts/build-upstream.sh
UPSTREAM_SHA="$(awk '$1 == "upstream_sha:" { print $2 }' upstream.lock)"
gh workflow run sign-images.yml --ref main -f upstream_sha="$UPSTREAM_SHA"
```

Executed: CODE-ONLY — promote the public-image path with two consecutive `gh workflow run mirror-images.yml --ref main` runs; promote the private-image path with the exact step 5 commands after P0-3b.
