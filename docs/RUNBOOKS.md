# Runbooks

Run every procedure from the repository root. Evidence labels, visitor commands, and pull-request checks are defined in [VERIFY.md](VERIFY.md).

## Local credentials

Local bootstrap uses the `orbit` AWS CLI profile for an MFA-protected IAM bootstrap identity whose access key remains only in `~/.aws/credentials`. Deactivate the key after bootstrap and re-enable it only for an authorized maintenance session. CI never uses it; CI authentication is OIDC-only.

## Bootstrap recovery

If local Terraform state is lost before the first migration to `backend.tf`, re-import each resource by address using the names in `bootstrap/`:

```bash
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
# Resolve <key-id> from alias/orbit-infra-79s5rw-signing.
terraform -chdir=bootstrap import aws_kms_key.signing <key-id>
terraform -chdir=bootstrap import aws_kms_alias.signing alias/orbit-infra-79s5rw-signing
terraform -chdir=bootstrap import 'aws_iam_openid_connect_provider.github[0]' <oidc-provider-arn>
terraform -chdir=bootstrap import 'aws_budgets_budget.monthly[0]' <account-id>:orbit-infra-79s5rw-monthly
```

Substitute the real 12-digit account ID locally; never place it in a tracked file. The LocalStack bootstrap recipes own `bootstrap/backend_override.tf` only when they create it. An existing file, symlink, or dangling symlink causes refusal before Terraform and remains unchanged.

After backend migration, recover a lost or corrupt state object by restoring a prior version:

```bash
aws s3api list-object-versions --bucket orbit-infra-79s5rw-tfstate --prefix bootstrap/terraform.tfstate
aws s3api copy-object --bucket orbit-infra-79s5rw-tfstate --copy-source "orbit-infra-79s5rw-tfstate/bootstrap/terraform.tfstate?versionId=<version-id>" --key bootstrap/terraform.tfstate
```

## Operator CIDR change

Read the CIDR without echoing it and update the repository secret without printing the value:

```bash
read -r -s -p "OPERATOR_CIDR: " OPERATOR_CIDR
echo
export OPERATOR_CIDR
printf '%s' "$OPERATOR_CIDR" | gh secret set OPERATOR_CIDR
```

Bind the active lease and recover all three digest-pinned image inputs. Each `jq -e` refusal is terminal:

```bash
ENV_ID=demo1
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
export TF_VAR_api_image="$(jq -er '.manifest.images.api_image' <<< "$LEASE_JSON")"
export TF_VAR_redis_image="$(jq -er '.manifest.images.redis_image' <<< "$LEASE_JSON")"
export TF_VAR_clickhouse_image="$(jq -er '.manifest.images.clickhouse_image' <<< "$LEASE_JSON")"
```

Generate the backend configuration, inspect the saved plan for only the intended ingress change, and apply that exact plan:

```bash
scripts/write-preview-backend.sh
make plan TARGET=aws ENV_ID="$ENV_ID" OPERATOR_CIDR="$OPERATOR_CIDR"
make apply TARGET=aws ENV_ID="$ENV_ID" OPERATOR_CIDR="$OPERATOR_CIDR"
```

This procedure is `CODE-ONLY` until the real-AWS promotion checks run.

## LocalStack CI mode

Dispatch the owner-only, non-scheduled lane from `main`:

```bash
gh workflow run session-apply.yml --ref main -f env_id=p4ci -f target=localstack -f mode=public
```

The workflow rejects collaborator reruns, starts the pinned emulator, uses test credentials in `us-east-1` with metadata disabled and no configured profile, applies the LocalStack bootstrap, registers QEMU and Buildx for ARM64, and builds the placeholder. Public mode uses the placeholder plus public Redis and ClickHouse images; private-ECR signature checks are AWS-only.

The job atomically opens an owner- and generation-bound lease, applies, verifies every service is on its Terraform task definition, probes the LocalStack ALB, and always runs Stage 1. After Stage 1 succeeds, it makes at most 20 in-job Stage 2 attempts, three seconds apart, and succeeds only at `closed`. It deletes versions and delete markers for the exact state key, records `in_job:true`, and never treats sibling prefixes as its inventory.

Curl exit 7 or 28 records the expected excluded-runner result. An HTTP 200 proves emulator routing, not security-group packet enforcement; other responses fail. Each hosted run has a fresh emulator, so it proves same-job control flow and GitHub queueing, not cross-run state or lease semantics. `session-destroy` therefore refuses `target=localstack`, and the AWS-only scheduled sweeper refuses it as well.

## IAM simulator lanes

The custom lane reads the ten raw policy documents from a post-bootstrap plan, renders the authored vectors, and writes a per-case JSON report. It accepts only `TARGET=aws` and routes every call through the repository wrapper:

```bash
TARGET=aws scripts/iam-simulate.sh \
  --plan <terraform-plan.json> \
  --vectors <vector-directory> \
  --report <custom-report.json>
```

Preview the temporary-role lane with the real call builder and zero AWS calls:

```bash
TARGET=aws scripts/iam-simulate-roles.sh \
  --plan <terraform-plan.json> \
  --vectors <role-vector-directory> \
  --report <role-report.json> \
  --expect-account <12-digit-account> \
  --dry-run
```

A live role-lane run also requires the exact opt-in and a custom report for the same vectors:

```bash
IAM_SIM_LANE_CONFIRM=create-real-iam-resources TARGET=aws \
  scripts/iam-simulate-roles.sh \
  --plan <terraform-plan.json> \
  --vectors <role-vector-directory> \
  --custom-report <custom-report.json> \
  --report <role-report.json> \
  --expect-account <12-digit-account>
```

Before any create, the lane checks the account, vector mode, submitted source hashes, plan documents, and sole caller principal. Every temporary role carries a run tag and a random 32-hex nonce; both are re-read before policy mutation and cleanup. Existing names are left for manual inspection, owned roles are removed in reverse order, absence is verified, and TERM or INT is deferred until cleanup and report writing finish.

`custom-isolated` and documents without an identity-role binding remain excluded. Mapped statements are concatenated in address order when they fit the 10,240-character role limit; oversized document sets use complete per-document passes. Duplicate Sids fail closed. Each inline policy is read back byte-for-byte, then receives a deterministic Sid-matching readiness probe with bounded retries before case simulation.

Each selected case runs once with the exact SCP exclusion and once as an effective-policy request. Required and forbidden Sids are checked per action/resource detail. A custom-versus-role mismatch is recorded as a divergence, while vector mismatch is a failing result; Organizations changes are attributed separately. A missing custom case is fatal.

The role report records `recorded_at`, the custom-report digest, source addresses and hashes, raw `policy_sha256`, and `redacted_policy_sha256` for the redacted `policy_document`. It also records propagation attempts, exclusions, agreements, principal divergences, and Organizations divergences. The final writer replaces account and caller identifiers plus the ownership nonce, then requires both redaction markers.

Render the Markdown report and provenance from completed JSON reports; omit `--role-report` when that lane was not run:

```bash
scripts/iam-simulate-report.sh \
  --custom-report <custom-report.json> \
  --role-report <role-report.json> \
  --recorded-on 2026-09-10 \
  --out-dir docs/assets
```

The renderer stages both files, runs artifact hygiene on input reports and outputs, derives outcomes from pair details, and publishes the report before provenance with rollback on either failed move. The pair must agree on publication metadata and generator commit. Never edit generated reports directly.

## Front-page evidence

Generate the storyboard from the clean commit containing its generator, then verify both outputs:

```bash
make storyboard
bash tests/storyboard-contracts.sh
```

For recordings, start LocalStack, apply its bootstrap once, and build the placeholder. The supply recording needs vhs, FFmpeg/ffprobe, and jq, but not OCR tooling:

```bash
make demo
make demo NAME=lease
make demo NAME=supply
# Or: make demo-all
```

Each invocation validates, tears down, renders provenance, and publishes as one guarded sequence. A mixed pair after interruption is exposed by the provenance contract and repaired by rerunning. The lease recorder owns one token and generation and inventories only its exact state key and `.tflock`. Do not edit generated assets.

## Sweeper

Every lease opens with a non-empty owner. Stage 1 `begin-cleanup` and Stage 2 `claim-stage2` require the owner from the same fresh read as status and generation. Legacy ownerless records refuse without mutation and require manual inspection.

The workflow runs at 03:17 UTC on `main`, only against AWS. More than 20 actionable leases fails discovery instead of truncating work. At most three environments run in parallel; each retains the `preview-<env_id>` concurrency group, and one failure does not cancel siblings. Dispatch an extra run when necessary:

```bash
gh workflow run sweeper.yml --ref main -f target=aws -f dispatch_note=manual
gh run list --workflow sweeper.yml --branch main --limit 5
```

Inspect a `closing` lease and invoke one exact environment sweep:

```bash
ENV_ID=demo1
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
jq '{status,generation,stage1_claim,stage2_claim,task_definitions:[.manifest.candidates[] | select(.resource_type == "ecs:task-definition") | .arn],last_verification:.manifest.verification_runs[-1],stage2_allowances:.manifest.stage2_allowances,last_stage2_run:.manifest.stage2_runs[-1]}' <<< "$LEASE_JSON"
TARGET=aws scripts/sweep.sh env "$ENV_ID"
```

An active Stage 1 claim blocks both stages. `DELETE_IN_PROGRESS` releases the matching Stage 2 claim and leaves `closing`. Pending non-task resources release Stage 2 and hand the lease back to Stage 1 before any state deletion. Indeterminate or partial Stage 2 work records `fail-stage2`, increments only `stage2_attempt`, clears the claim, retains remaining state, and leaves `closing`. CAS loss exits 3; re-read and do not retry an active claim.

Closed leases retain their proof for seven days. Only an older lease is replaced by an ETag-conditioned minimal `deleted` tombstone; exactly seven days remains retained.

### Exhausted closing retry budget

A lease with `manual_intervention_required=true` and `cleanup_attempt >= 3` or `stage2_attempt >= 3` has exhausted its automatic budget. Inspect the last verification or Stage 2 error, repair only that condition, then use the audited Stage 1 force-retry path below. The sweeper never supplies `--force-retry`.

## Manual lease recovery

1. Read the durable lease once and retain Terraform state as evidence and retry input:

```bash
ENV_ID=demo1
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
jq '{status,generation,owner,stage1_claim,stage2_claim,cleanup_attempt,stage2_attempt,next_retry_at,manual_intervention_required,initial_target:.manifest.target,initial_mode:.manifest.mode,last_verification:.manifest.verification_runs[-1]}' <<< "$LEASE_JSON"
```

If Stage 1 owns the lease, do not close or sweep. If a Stage 2 claimant is confirmed dead, release only its exact token and generation, then re-read. The nightly sweeper can take over a two-hour-old claim with the same fresh-read CAS and audit record.

```bash
GENERATION="$(jq -er '.generation' <<< "$LEASE_JSON")"
CLAIM="$(jq -er '.stage2_claim.token | select(type == "string" and length > 0)' <<< "$LEASE_JSON")"
TARGET=aws scripts/lease.sh release-stage2 "$ENV_ID" --generation "$GENERATION" --claim "$CLAIM"
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
```

2. For VPC deletion blocked by orphaned ENIs, derive the exact VPC and inspect only redacted fields. Repair the owning endpoint, load balancer, or ECS service; never delete a requester-managed ENI directly:

```bash
VPC_ID="$(jq -er '.manifest.candidates[] | select(.resource_type == "ec2:vpc") | .id' <<< "$LEASE_JSON" | head -n1)"
TARGET=aws scripts/aws-cli.sh ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[].{id:NetworkInterfaceId,status:Status,requester_managed:RequesterManaged,description:Description}' --output json
```

3. For a non-empty data bucket, derive its name, verify the environment suffix, inspect keys, and empty only that unversioned bucket:

```bash
BUCKET="$(jq -er '.manifest.candidates[] | select(.resource_type == "s3:bucket") | .id' <<< "$LEASE_JSON" | head -n1)"
case "$BUCKET" in *-"$ENV_ID"-data) ;; *) echo "refusing unexpected bucket: $BUCKET" >&2; exit 1 ;; esac
TARGET=aws scripts/aws-cli.sh s3api list-objects-v2 --bucket "$BUCKET" --max-items 20 --query 'Contents[].Key' --output json
TARGET=aws scripts/aws-cli.sh s3 rm "s3://$BUCKET" --recursive
```

4. Before the limit, wait until `next_retry_at`, refresh the lease, and resume the normal path:

```bash
make close TARGET=aws ENV_ID="$ENV_ID" OPERATOR_CIDR="$OPERATOR_CIDR"
```

5. After a third Stage 1 failure, re-read status, generation, and owner together, then claim one audited force retry only after the targeted repair:

```bash
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
GENERATION="$(jq -er '.generation' <<< "$LEASE_JSON")"
STATUS="$(jq -er '.status | select(. == "open" or . == "closing" or . == "cleanup_failed")' <<< "$LEASE_JSON")"
OWNER="$(jq -er '.owner | select(type == "string" and length > 0)' <<< "$LEASE_JSON")"
TARGET=aws scripts/close-env.sh --force-retry --generation "$GENERATION" --from "$STATUS" --owner "$OWNER" "$ENV_ID"
```

6. Confirm the attempt and audit incremented, state remains retained, and status is `closing` after success or `cleanup_failed` with a new exact error:

```bash
TARGET=aws scripts/lease.sh get "$ENV_ID" | jq '{status,generation,owner,cleanup_attempt,manual_intervention_required,cleanup_retry_audit,last_verification:.manifest.verification_runs[-1]}'
```

A forced run may take over a confirmed-dead stale Stage 1 claim and records the cleared claim. Never force while its process may run. If status is `closing`, return to the Sweeper procedure. A pending task definition consumes Stage 2 retries, not Stage 1 retries. Only the exact recorded LocalStack inactive-task allowance exists; stale tags, retained list entries, deleted endpoints, ENI ownership, and bucket emptiness are never generalized allowances.

## Rotate secrets

Use hidden `gh` prompts; never pass values on the command line, echo them, or write them to a file:

```bash
gh secret set LOCALSTACK_AUTH_TOKEN
gh secret set INFRACOST_API_KEY
gh secret set OPERATOR_CIDR
gh secret set AWS_KMS_SIGNING_KEY_ARN
gh secret set AWS_ROLE_PLAN_READER
gh secret set AWS_ROLE_DEPLOYER
gh secret set AWS_ROLE_PUBLISHER
gh secret list
```

Exercise each consumer: OIDC smoke for role ARNs, a LocalStack session for its token, an owner pull request for Infracost, the CIDR procedure for ingress, and the image workflows for the publisher and signing key.

```bash
gh workflow run oidc-smoke.yml --ref main
gh workflow run session-apply.yml --ref main -f env_id=rot1 -f target=localstack -f mode=public
gh workflow run mirror-images.yml --ref main
```

## Re-sign an already-signed digest

Re-dispatch both producers with the existing lock values, then inspect their runs:

```bash
UPSTREAM_SHA="$(awk '$1 == "upstream_sha:" { print $2 }' upstream.lock)"
gh workflow run sign-images.yml --ref main -f upstream_sha="$UPSTREAM_SHA"
gh workflow run mirror-images.yml --ref main
gh run list --workflow sign-images.yml --branch main --event workflow_dispatch --limit 3
gh run list --workflow mirror-images.yml --branch main --event workflow_dispatch --limit 3
```

Each producer rescans and publishes a fresh scan predicate. Valid signatures are not duplicated; build and canonical SBOM attestations are added only when no matching predicate exists. Existing destination images must retain the locked digest.

## Refresh a stale scan attestation

AWS apply accepts a passing scan predicate for 10 days by default; `scan_freshness_days` may be 1 through 60. Mirrors refresh weekly on Monday at 06:00 UTC. Upstream mode has no schedule, so run `sign-images.yml` for the locked commit inside the selected window.

Re-run `sign-images.yml` for an upstream API or ClickHouse digest; use `mirror-images.yml` for the placeholder, Redis, or mirrored ClickHouse. Missing, malformed, future, failed, wrong-digest, or wrong-version predicates require a successful producer run; never widen the window to accept invalid evidence. A placeholder dependency-lock change produces a new digest on the next mirror run.

## Image bump

1. For Redis or ClickHouse, resolve the new ARM64 manifest digest and update the matching source and digest in `mirror-images.lock`. Keep repository fields fixed. For the placeholder, set its digest and source SHA to explicit pending markers, dispatch once, then replace both from the run.

2. Run the producer twice to prove both publication and idempotency:

```bash
gh workflow run mirror-images.yml --ref main
gh workflow run mirror-images.yml --ref main
```

3. A ClickHouse mirror change alters the private ClickHouse build inputs. Set `repo_build_inputs_sha256` to a pending marker, run the archive-only builder without pushing, and record its archive hash, build-input hash, and three local IDs:

```bash
UPSTREAM_DIR="${UPSTREAM_DIR:?set UPSTREAM_DIR to the clean locked clone}"
PUSH=0 UPSTREAM_DIR="$UPSTREAM_DIR" scripts/build-upstream.sh
```

4. For an upstream commit bump, update `upstream_sha` and repeat the no-push build. The builder verifies origin, exact HEAD, cleanliness, archive hash, and repository input hash.

5. After authorized registry setup, push the exact builds and dispatch signing:

```bash
ECR_REGISTRY="${ECR_REGISTRY:?set the private ECR registry without printing it}"
PUSH=1 UPSTREAM_DIR="$UPSTREAM_DIR" ECR_REGISTRY="$ECR_REGISTRY" scripts/build-upstream.sh
UPSTREAM_SHA="$(awk '$1 == "upstream_sha:" { print $2 }' upstream.lock)"
gh workflow run sign-images.yml --ref main -f upstream_sha="$UPSTREAM_SHA"
```
