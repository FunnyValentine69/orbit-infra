# Runbooks

Evidence gates: LocalStack apply, Stage 1, and the successful in-job Stage 2 allowance/close path are LOCALSTACK-VERIFIED in CI (Phase 4 run 33757937265; post-merge dispatch run 33825140591 from main 9b253b6; stage-claim exclusivity, the pending hand-backs, and prune are fixture-verified only); the nightly AWS sweeper is CODE-ONLY until P0-3b. Run every procedure from the repository root.

## PR review gates

Every fork and owner PR runs the secret-free `gates` job with policy-size
explicitly skipped because that check renders a LocalStack plan. Owner PRs
also run the `plan-localstack` job, which executes policy-size after the
emulator health wait with the LocalStack environment contract. Because source
mode is only Sid-keyed on fork PRs, `.github/workflows/iam-matrix-plan.yml`
closes the exact-field drift window on the next push to `main` by applying the
LocalStack bootstrap before `make iam-matrix-plan`; a weekly schedule is the
backstop, and default-branch dispatch is also available. Local
`scripts/gates.sh` runs keep policy-size required by default.

The `oidc-smoke.yml` jobs run on same-repository PR runs and are skipped on fork
PRs and on runs whose `github.actor` is `dependabot[bot]` (all four: `decode-
subject` and the three `assume-*` jobs). Before P0-3b each `assume-*` job fails
at its first `Require AWS_ROLE_*` step with exit 1, because the real-AWS
bootstrap has not produced the role ARNs and the post-apply `gh secret set`
commands have not published `AWS_ROLE_PLAN_READER`, `AWS_ROLE_DEPLOYER`, and
`AWS_ROLE_PUBLISHER`. Those three red checks are the expected state on same-
repository PRs until then. `gates` runs on every PR; `plan-localstack` and
`infracost` run only on PRs authored by the repository owner; those three are
the checks that must be green.

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

The LocalStack `make bootstrap-plan TARGET=localstack` and `make
bootstrap-apply TARGET=localstack` paths own `bootstrap/backend_override.tf`
only when they create it. If that path already exists as a regular file or
symlink, including a dangling symlink, the target refuses before Terraform and
leaves the operator-owned entry unchanged. Move or remove an intentional
operator override yourself before rerunning; the recipe never adopts it.

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
   runs owner-bound Stage 1 and, only when Stage 1 succeeds, in-job Stage 2
   (a Stage-1 failure leaves `cleanup_failed`, and an absent or foreign lease
   skips both); when every
   recorded task definition confirms deletion the terminal lease is `closed`
   with `manifest.stage2_runs[-1].in_job=true`, and a still-pending definition
   leaves it `closing`. Either way the lease lives on that job's fresh
   emulator and is not observable from a later runner.

```
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
jq -e '.status == "open" and (.owner | type) == "string"
  and .manifest.target == "aws"
  and (.manifest.mode == "public" or .manifest.mode == "upstream")
  and all(.manifest.images.api_image, .manifest.images.redis_image, .manifest.images.clickhouse_image;
    type == "string" and length > 0)' <<< "$LEASE_JSON"
```

Executed: the apply/acceptance/Stage-1 portion is LOCALSTACK-VERIFIED in CI
2026-09-03 from the recorded Phase 4 run. The same-job Stage 2 is
LOCALSTACK-VERIFIED in CI 2026-09-03 by the post-merge dispatch `gh workflow run
session-apply.yml --ref main -f env_id=sw1 -f target=localstack -f mode=public`
(run 33825140591 from main 9b253b6: env sw1 reached `closed`, state versions removed).

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

3. Confirm that a successful Stage 1 retained Terraform state evidence,
   cleared `stage1_claim`, and left the lease `closing` for the nightly sweeper.
   `closed` is not a Stage 1 success state; it is written only after Stage 2
   deletes every state version:

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
Stage 1 then holds an exclusive claim until its success or failure CAS.

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
manifest, the same job runs `make apply`, waits for every enabled ECS service,
checks that each service reached its applied task definition, probes the
Terraform `api_url` output (the LocalStack ALB) from the excluded runner CIDR,
records the ALB URL in the summary, and always runs Stage 1. After a successful
Stage 1, which clears its claim, it runs up to 20 `SWEEP_IN_JOB=true
scripts/sweep.sh env "$ENV_ID"` attempts, sleeping three seconds between a
remaining `closing` status. The step succeeds only when the lease is `closed`;
an in-job failure or exhausted bound means state versions may remain and must be
handled with the manual-release procedure below. Stage 2 consumes the recorded LocalStack
allowance, deletes all
versions and delete markers for the emulator's S3 state key, records
`in_job:true`, and sets the lease `closed`. A refused or
timed-out probe (curl exit 7 or 28) records the negative-CIDR outcome. If the
LocalStack edge responds, `/health` must return HTTP 200; any other HTTP status
or curl error fails the step. LocalStack routes ALB DNS through its shared edge
and does not document source-CIDR enforcement, so an HTTP 200 proves endpoint
routing but not the real-AWS security-group boundary. On AWS, any HTTP response
from the excluded runner remains a failure.

Now that the post-merge `session-apply` dispatch has run (run 33825140591),
this mode proves the workflow's successful close-and-sweep bootstrap → lease →
apply → service acceptance → Stage 1 → Stage 2 control flow on one runner,
while stage-claim exclusivity and the pending hand-back branches remain
fixture-verified. It does not prove GitHub OIDC, real-AWS IAM,
private ECR/KMS supply-chain verification, AWS Budgets, ECS Exec, real
security-group packet enforcement, or a cross-job destroy. The scheduled
sweeper is AWS-only and refuses `target=localstack` because emulator state is
job-local. The post-merge dispatch ran as run 33825140591 (main 9b253b6);
in-job Stage 2 is LOCALSTACK-VERIFIED in CI. Every
LocalStack CI run uses a fresh runner and fresh emulator, so the gh-driven
dispatch test proves only GitHub concurrency queueing on this target. Lease CAS,
refusal on `open`/`closing`/`cleanup_failed`, and generation increments are
proved locally against one emulator by `tests/localstack-concurrency.sh`. A
`session-destroy.yml` dispatch with `target=localstack` is refused because a
fresh runner cannot recover the prior emulator or local state. LocalStack CI
uses licensed credits, so this lane is dispatch-only and must never be added to
a schedule.

## IAM simulator lanes

Phase 3 supplies the authored vector directory. The custom lane reads the ten
raw policy strings from a post-bootstrap Terraform plan, renders vector
templates, and writes a per-case JSON report. It refuses every target except
real AWS and routes all simulator calls through the repository wrapper:

```
TARGET=aws scripts/iam-simulate.sh \
  --plan <terraform-plan.json> \
  --vectors <vector-directory> \
  --report <custom-report.json>
```

Preview the role lane without its opt-in. `--dry-run` uses the real call builder,
prints the caller check, every tagged projection-role create and inline-policy
put, both simulations for every selected case, reverse cleanup, and absence
checks; it makes zero AWS calls. Its create-role inventory uses the same trust
policy builder as a live run, with the invoking identity represented by the
redacted principal placeholder. With the complete authored vector directory and
current plan this inventory has eight projection passes: one combined
plan-reader pass, six per-document deployer passes, and one publisher pass:

```
TARGET=aws scripts/iam-simulate-roles.sh \
  --plan <terraform-plan.json> \
  --vectors <role-vector-directory> \
  --report <role-report.json> \
  --expect-account <12-digit-account> \
  --dry-run
```

A real role-lane run additionally requires the literal environment value
`IAM_SIM_LANE_CONFIRM=create-real-iam-resources` and the custom-lane report for
the same vectors. Before the caller check or first role create, each custom
record's mode and submitted source-policy SHA-256 must match the current vector
and plan document. The plan-derived account must be the authored
`000000000000` placeholder or equal `--expect-account`; a third account fails
before the caller check or any role create. After `sts get-caller-identity`, every
temporary role's trust policy must name exactly the returned caller Arn as its
sole AWS principal; an account-root principal is refused before create-role. The
opt-in string authorizes only the roles carrying both the run tag and a
per-invocation
`OrbitIamSimulationNonce`: 32 lowercase hexadecimal characters read from
`/dev/urandom`. The lane verifies both tags on every created role before the
first policy put and re-reads both immediately before each cleanup mutation. It
treats `EntityAlreadyExists` as manual cleanup without deleting it, removes
owned roles in reverse order, and requires `NoSuchEntity` afterward. The
inline-policy cleanup marker is persisted before the put; an unattached
policy's `NoSuchEntity` is therefore safe to continue past. TERM and INT
received during cleanup are recorded until cleanup, absence verification, and
report writing finish, then returned as their signal-derived status.

The role lane consumes the same `custom` vectors as the custom lane.
`custom-isolated` cases are excluded because an isolated single-statement
simulation has no principal equivalent, and documents without an identity-role
binding remain excluded. For each selected role, mapped documents are sorted by
address and their `Statement` arrays are concatenated. A combined policy at or
below 10,240 whitespace-stripped characters uses one role. If it is larger,
each source document uses its own complete create, put, simulate, and delete
pass; no document's cases are dropped. A duplicate Sid across documents in a
combined role fails closed with both source addresses.

After each inline-policy put, the lane first reads the policy back until its
document equals the submitted bytes, then sends one SCP-excluded readiness
probe. The probe uses the first decision case in the full, pre-`--only` vector
inventory for that projection whose expectation requires a matched Sid; either
an allowed statement or an explicit deny statement is a valid visibility
witness, while attribution-only cases are excluded. Both checks allow five
attempts with 1, 2, 4, and 8 second backoff, and the role report records the
observed `{readback, probe}` counts in `propagation_attempts` for every
projection. Exhaustion fails the run and still enters normal cleanup.

Every selected case runs first with the exact `{"PolicyType":"scp"}` exclusion
and then without an exclusion. Required and forbidden Sids are checked on every
action/resource detail independently; their union is retained only for display.
The SCP-excluded result is compared to the custom
report's observed decision. A mismatch is a non-failing divergence record with
the deciding projection, both decisions, both matched-Sid lists, and the run or
runs where it appears. The default request is the effective-policy result; each
action/resource decision changed by Organizations is separately attributed and
counted. Any loaded vector case missing from the custom report is fatal:

```
IAM_SIM_LANE_CONFIRM=create-real-iam-resources TARGET=aws \
  scripts/iam-simulate-roles.sh \
  --plan <terraform-plan.json> \
  --vectors <role-vector-directory> \
  --custom-report <custom-report.json> \
  --report <role-report.json> \
  --expect-account <12-digit-account>
```

At run start, the lane snapshots the custom report and evaluates only that
snapshot. The role report records UTC `recorded_at`, the exact snapshot's
`custom_report_sha256`, each projection's source addresses, source-policy
SHA-256 hashes, `propagation_attempts`, selected and excluded case counts by reason, agreements,
principal/custom divergences, and Organizations divergences. The AWS-managed
`ReadOnlyAccess` attachment has no inline equivalent and is always recorded as a
role-lane exclusion. A single final redaction replaces both the live account and
any non-placeholder plan account with `000000000000`; the report records
`plan_account_redacted`, and the ownership nonce is replaced with `<redacted>`
so a report cannot replay either ownership value. The caller identity is replaced
in full with `arn:aws:iam::000000000000:<redacted-principal>`; the writer refuses
any report retaining the caller's user or role name. The shared writer then
applies a final whole-report identifier redaction and records
`redaction_applied: true`. The cleanup paths remain contract-tested offline. A
real role-lane execution on 2026-09-10 recorded 156 cases: 155 passed and 1
failed on the same `SnsSubscriptionManage` finding as the custom lane, with 153
custom-lane agreements, 3 divergences, and zero residue; see
`docs/assets/iam-simulation-role-report.json`.

Render the publishable Markdown pair from the completed JSON reports. Omit the
`--role-report` option when only the custom lane was run:

```
scripts/iam-simulate-report.sh \
  --custom-report <custom-report.json> \
  --role-report <role-report.json> \
  --recorded-on 2026-09-10 \
  --out-dir docs/assets
```

The renderer requires a role report to attest `account_redacted: true`, writes
both files in a temporary directory, and invokes `scripts/artifact-hygiene.sh`
on each supplied JSON lane report and both rendered Markdown files before
publication. Only after every check passes does it publish the report and then
the provenance last, rolling the pair back if either move
fails. Both files record the publication date and generator commit; the
Evidence join refuses a disagreeing pair. A violation leaves the output
directory untouched and prints the checker's `FAIL:` line. Custom-lane pass
cells, counts, and findings are re-derived from observed decisions and
required/forbidden Sids rather than trusting the stored `pass` field. Role
divergence rows show the vector expectation separately from custom observed, and
mixed resource results are compared with `expect.resource_decisions`.

## Front-page evidence

Generate the storyboard only from the clean commit that contains its generator:

```
make storyboard
```

That command writes `docs/assets/storyboard.svg` and
`docs/assets/STORYBOARD_PROVENANCE.md`; do not edit either output. Re-run
`bash tests/storyboard-contracts.sh` before publishing them together.

For the recordings, start LocalStack, apply the LocalStack bootstrap once, and
build the placeholder image. Record lifecycle, lease, and supply-chain evidence
in order with `make demo`, `make demo NAME=lease`, and `make demo NAME=supply`,
or run the same sequence with `make demo-all`. Each recorder invocation runs
validation, teardown, provenance rendering, and publication as one guarded sequence;
publication uses two independent renames, so interruption can leave a mixed pair
that the provenance contract exposes and a rerun repairs. Do not edit those
generated files. The lease recording owns only its unique owner token and
generation, and points here when a claim or manual-recovery state prevents safe
cleanup.

## Sweeper

The workflow runs nightly at 03:17 UTC; the odd minute avoids common
top-of-hour scheduling congestion. It runs only on `main` and only against
AWS. A manual LocalStack target is intentionally refused because the emulator
and its state do not survive the `session-apply` job. LocalStack apply and
Stage 1 are LOCALSTACK-VERIFIED in CI by the Phase 4 run; the post-merge
dispatch below ran as run 33825140591 (main 9b253b6), and in-job LocalStack
Stage 2 is LOCALSTACK-VERIFIED in CI; this nightly AWS path is CODE-ONLY until P0-3b. Dispatch an
extra AWS run with a correlation note when needed:

```
gh workflow run sweeper.yml --ref main -f target=aws -f dispatch_note=manual
gh run list --workflow sweeper.yml --branch main --limit 5
```

The discover summary lists every lease classification and the number of
actionable environments. More than 20 actionable leases fails discovery
instead of truncating cleanup. Each environment gets an independent summary
with `before`, `after`, and `result`; account-shaped numbers are masked. The
matrix runs at most three environments in parallel, retains each queued
`preview-<env_id>` job behind apply/destroy, and one failure does not cancel
siblings.

If a lease remains `closing`, inspect only the current status, recorded
task-definition candidates, Stage 1 verification, and Stage 2 allowances:

```
ENV_ID=demo1
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
jq '{status,generation,stage1_claim,stage2_claim,task_definitions:[.manifest.candidates[] | select(.resource_type == "ecs:task-definition") | .arn],last_verification:.manifest.verification_runs[-1],stage2_allowances:.manifest.stage2_allowances,last_stage2_run:.manifest.stage2_runs[-1]}' <<< "$LEASE_JSON"
TARGET=aws scripts/sweep.sh env "$ENV_ID"
```

An active `stage1_claim` means Stage 1 still owns the generation; repeat
Stage 1 and Stage 2 both refuse it. Successful Stage 1 leaves that field null.
A printed `DELETE_IN_PROGRESS` ARN is pending, not an error; the sweeper
releases its matching claim and leaves the lease `closing` for the next nightly
run. Stage 2 also requires zero pending non-task results; otherwise it releases
its claim and hands the `closing` lease back to Stage 1 for re-verification
before any state deletion.

### Exhausted closing retry budget

A `closing` lease with `manual_intervention_required=true` and either
`cleanup_attempt >= 3` or `stage2_attempt >= 3` has spent its automatic budget.
Inspect `manifest.verification_runs[-1]` for a Stage 1 hand-back or `error` for a
Stage 2 failure, resolve that exact condition, then use the audited
`begin-cleanup --force-retry` path through `close-env.sh --force-retry`. The
sweeper never supplies `--force-retry`.

An indeterminate describe or state delete invokes `fail-stage2`, clears the
matching claim, increments `stage2_attempt`, leaves the lease `closing`, and
retains state wherever deletion stopped. A Stage 2 CAS loss
exits 3 without closing the lease or deleting a concurrently added state
version. Re-read the lease; do not rerun while it carries an active claim.

After Stage 2 records zero state versions, `closed` leases remain readable for
seven days. The first later sweep replaces the current lease with a minimal
`deleted` generation tombstone under its ETag precondition. A lease exactly
seven days old is retained; only an older lease becomes a tombstone. `sweep.sh
env` on a younger `closed` lease prints the retention no-op reason.

LocalStack Stage 2 is proved only inside the owner-bound `session-apply` job.
The promotion dispatch that produced run 33825140591 was:

```
gh workflow run session-apply.yml --ref main -f env_id=sw1 -f target=localstack -f mode=public
```

The post-merge dispatch above ran as run 33825140591 (main 9b253b6); the
in-job LocalStack Stage 2 is LOCALSTACK-VERIFIED in CI. The nightly AWS
workflow remains CODE-ONLY until P0-3b.

## Manual lease recovery

1. Bind the environment, read the durable lease once, and inspect only its
   lifecycle fields and most recent exact-resource outcomes. Keep the retained
   Terraform state; it is evidence and an input to every retry:

```
ENV_ID=demo1
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
jq '{status,generation,owner,stage1_claim,stage2_claim,cleanup_attempt,stage2_attempt,next_retry_at,manual_intervention_required,initial_target:.manifest.target,initial_mode:.manifest.mode,last_verification:.manifest.verification_runs[-1]}' <<< "$LEASE_JSON"
```

If `stage1_claim` is present, Stage 1 owns the lease; do not start Stage 2
or another close. If `status` is `closing` and `stage2_claim` is present after
an interrupted or CAS-refused sweep, first confirm that the recorded claimant
is no longer running. Release only that token and generation, then re-read before rerunning
the sweeper. The nightly sweeper automatically attempts the same CAS-safe
takeover after a claim is two hours old and records the cleared claim in
`cleanup_retry_audit`; manual release remains available for an earlier confirmed
failure. The release itself is one fresh-read CAS and refuses changed state with
exit 3:

```
GENERATION="$(jq -er '.generation' <<< "$LEASE_JSON")"
CLAIM="$(jq -er '.stage2_claim.token | select(type == "string" and length > 0)' <<< "$LEASE_JSON")"
TARGET=aws scripts/lease.sh release-stage2 "$ENV_ID" --generation "$GENERATION" --claim "$CLAIM"
LEASE_JSON="$(TARGET=aws scripts/lease.sh get "$ENV_ID")"
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
   intentionally disabled on the ephemeral data bucket. The multipart-abort
   lifecycle rule does not change this procedure; the bucket is still unversioned:

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
STATUS="$(jq -er '.status | select(. == "open" or . == "closing" or . == "cleanup_failed")' <<< "$LEASE_JSON")"
OWNER="$(jq -er '.owner | select(type == "string" and length > 0)' <<< "$LEASE_JSON")"
TARGET=aws scripts/close-env.sh --force-retry --generation "$GENERATION" --from "$STATUS" --owner "$OWNER" "$ENV_ID"
```

6. Confirm `cleanup_attempt` incremented, `cleanup_retry_audit` gained the
   forced attempt, state remains retained, and the lease is either `closing`
   after successful stage 1 or `cleanup_failed` with a new exact error:

```
TARGET=aws scripts/lease.sh get "$ENV_ID" | jq '{status,generation,owner,cleanup_attempt,manual_intervention_required,cleanup_retry_audit,last_verification:.manifest.verification_runs[-1]}'
```

The same forced run takes over a stale stage-1 claim left by a killed
stage-1 job and records it as cleared_stage1_claim in the audit entry;
never force while the previous stage-1 process may still be running.

If step 6 leaves `closing`, use the Sweeper procedure above. Do not force Stage
1 merely because a task definition is still `DELETE_IN_PROGRESS`; Stage 2
will retry it without consuming the Stage 1 attempt budget.

The exact verifier owns all `gone`, `pending`, `live`, and `indeterminate`
predicates. The only LocalStack allowance remains an unsupported
`DeleteTaskDefinitions` response for an already-`INACTIVE` task definition;
its ID, ARN, error code, and timestamp are persisted. Stale tags, retained
cluster-list entries, VPC endpoints in `deleted`, ENI ownership, and S3
emptiness are never generalized allowances.

Executed: LOCALSTACK-VERIFIED 2026-09-03 — an applied `rbstuck` environment whose lease was driven to `cleanup_failed` with cleanup_attempt 3 and manual_intervention_required refused the automatic close with exit 3; the audited force retry destroyed all 59 resources and left `closing`, cleanup_attempt 4, and one `cleanup_retry_audit` entry (steps 2 and 3 remain CODE-ONLY: no ENI orphan or non-empty bucket occurred). That recorded run predates the current generation/status-bound interface; repeat it only with the step 5 command above.

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

3. Inspect both runs. Each workflow re-runs its scans, publishes a fresh scan
   attestation, and performs final verification. An existing valid signature is
   not duplicated; build and canonical SBOM attestations are added only when no
   matching predicate exists. Existing destination images must still match the
   locked digest; a mismatch fails.

```
gh run list --workflow sign-images.yml --branch main --event workflow_dispatch --limit 3
gh run list --workflow mirror-images.yml --branch main --event workflow_dispatch --limit 3
```

Executed: CODE-ONLY — promote with `gh workflow run sign-images.yml --ref main -f upstream_sha="$(awk '$1 == "upstream_sha:" { print $2 }' upstream.lock)"` and `gh workflow run mirror-images.yml --ref main` after P0-3b.

## Refresh a stale scan attestation

AWS applies accept a passing scan attestation for at most 10 days by default.
`scan_freshness_days` may override that window with an integer from 1 through
60. The weekly `mirror-images` schedule runs Monday at 06:00 UTC, leaving a
three-day margin inside the default window. Upstream mode has no scheduled
producer: dispatch `sign-images.yml` for the locked commit within the selected
window before starting an upstream-mode apply.

A stale-scan failure names the affected image label and digest. Re-run
`sign-images.yml` when the digest is an upstream API or ClickHouse image. Re-run `mirror-images.yml`
when it is the placeholder, Redis, or mirrored ClickHouse digest, then retry the
apply. A missing, malformed, future-dated, failed, wrong-digest, or wrong-Trivy-
version predicate is also refused and must be replaced by a successful producer
run; do not widen the window to accept an invalid predicate.

The hash-locked placeholder dependency set changes its image digest. The first
real-AWS `mirror-images.yml` run after this change is therefore expected to
publish a new placeholder digest for `mirror-images.lock`.

Executed: CODE-ONLY — the producer and apply paths require the real-AWS bootstrap after P0-3b.

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
