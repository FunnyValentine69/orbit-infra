# ADR 0006: Preview environment lease lifecycle

Status: Accepted (2026-09-02; amended 2026-09-03). Evidence: local apply/close is LOCALSTACK-VERIFIED; the LocalStack session workflow is CODE-ONLY until its first owner dispatch; every real-AWS behavior is CODE-ONLY until the promotion gate P0-3d runs.

## Context

Environments are created/destroyed by independent CI dispatches that can be interrupted, retried, or overlap the nightly sweeper. Without a durable, race-safe state record, a crashed apply or overlapping destroy could orphan billable resources.

## Decision

Each `env_id` has a durable lease at `leases/<env_id>.json` with states `open → closing → closed | cleanup_failed` and a monotonically increasing `generation`. Every transition is a compare-and-swap (S3 conditional write on the ETag, asserting prior state/generation) — two writers can never both win. Apply order: runner-CIDR check → lint → checkov → verify every selected image signature and attestation against the lock files → create lease (only if none exists or `closed`, generation N+1) → record the mode and resolved image references → init → plan → apply; static and supply-chain gate failures never create a lease or resources. The apply workflow emits acquisition state and generation only after its CAS open succeeds. Its failure handler runs only for that acquisition and passes the generation to `close-env.sh`, which refuses without a transition if the current lease generation differs. On AWS, close reuses the three resolved image references in the lease manifest so Terraform can load the configuration before destroy; a missing reference fails closed. The LocalStack lane continues to use its local defaults.

The session workflows accept `target=aws|localstack` and record the target in
the lease manifest. The AWS path retains the independent apply and destroy
dispatches. LocalStack state and the emulator live only on one hosted runner,
so `session-apply` performs the complete bootstrap → apply → acceptance →
stage-1 close cycle in one job and always closes its acquired generation at
the end. `session-destroy target=localstack` refuses with a clear error because
a fresh job has neither the emulator nor its state; it cannot prove cross-job
destroy. The owner-only LocalStack job uses test credentials and never assumes
or reads an AWS role. This asymmetry is intentional and is not evidence for
the real-AWS cross-dispatch lifecycle.

Every LocalStack CI run starts on a fresh hosted runner with a fresh emulator.
Therefore the gh-driven dispatch-ordering test can prove only GitHub
concurrency queueing on the LocalStack target; it cannot observe cross-run
lease CAS, lease-state refusals (`open`/`closing`/`cleanup_failed`; the
static `target=localstack` input refusal it does observe is not lease state),
retained state, or generation increments. Those
lease semantics are proved locally by `tests/localstack-concurrency.sh`, which
runs both environments against one already-running LocalStack instance.

Close is two-stage since task definitions delete asynchronously (up to 24h) while a hosted job caps at 6. Stage 1 sets `closing`, persists a retry-merged manifest, discovers and scales every ECS service to zero, destroys with retries, requests task-definition deletion, and verifies every recorded candidate. A successful stage 1 ends `closing`, retaining the Terraform state object and its versions. Stage 1 never sets `closed`. Stage 2 (sweeper) re-checks the manifest; once every task definition is deleted, it removes state versions and sets `closed`. The sweeper shares the `preview-<env_id>` concurrency group with apply/destroy so running jobs do not overlap. Both session workflows set `queue: max` (a documented GitHub Actions concurrency property since 2026-05-07, allowed only with `cancel-in-progress: false`) so every pending dispatch is retained and a queued destroy is never displaced; a review claim that the key is unsupported was refuted against the workflow-syntax reference and the changelog. The lease compare-and-swap, generation check, and retry-safe state machine are the correctness boundary; the workflow queue is only serialization. If a destroy is displaced while pending, the operator must re-dispatch it. `closed` leases prune after 7 days.

### Cleanup verifier amendment (2026-09-02)

The stage-1 candidate set is created before destroy and is the union of the prior manifest, identifiers from Terraform state, ECS discovery, and the pre-destroy tag inventory. Resource Groups Tagging API results are discovery evidence only. They are re-queried at 0, 2, 4, 8, 16, and 30 seconds after destroy and unioned into the candidate set, but neither a nonempty nor an empty tag response decides liveness. A tag query is successful only when its zero-exit stdout is a JSON object whose `ResourceTagMappingList` is an array; every other response is an indeterminate observation, and any indeterminate scheduled observation adds an unsupported `tag-inventory-incomplete` candidate so stage 1 fails closed.

One exact-resource verifier assigns one result to every candidate and persists every iteration:

- `gone`: absent, terminal, or non-billable under the resource-specific predicate. This includes VPC endpoints in `deleted`; ECS clusters/services in `INACTIVE`; ECS tasks in `STOPPED`; and task definitions in `INACTIVE` or `DELETE_IN_PROGRESS`. A successful ECS describe response with no matching cluster/service/task is `gone` only when every failure entry names the exact candidate ARN with reason `MISSING`; an empty collection with empty failures is indeterminate.
- `pending`: a recognized deletion transition, such as a VPC endpoint in `deleting`, or a secret with `DeletedDate` when force-delete semantics were not recorded.
- `live`: the exact API proves the resource remains usable or active.
- `indeterminate`: the exact probe timed out, was denied, returned malformed data, or has an unsupported resource type.

Stage 1 retries `pending`, post-destroy `live`, and transient `indeterminate` results for up to five minutes, with backoff capped at 30 seconds. Partial results are appended to `manifest.verification_runs` on every iteration. A non-zero verifier exit or malformed verifier result is routed through the same `cleanup_failed` lease transition with a recorded error. At the deadline, `live` or `indeterminate` results set `cleanup_failed`; `pending` may remain for stage 2. Stale tag records whose exact probes are `gone` are persisted under `manifest.stale_tag_entries` and never fail stage 1.

All cleanup and lease AWS CLI calls pass through `scripts/aws-cli.sh`, with five-second connect and 20-second read timeouts inside a 30-second process-group deadline. The ECS service-stability waiter is the deliberate exception: it gets a 660-second outer deadline for the AWS CLI's ten-minute wait window. `TARGET` is mandatory. `localstack` requires an explicit localhost endpoint, test credentials, disabled metadata lookup, and no `AWS_PROFILE`; `aws` rejects a LocalStack endpoint.

The only stage-1 emulator allowance is `localstack-delete-task-definitions-inactive`: `TARGET=localstack`, the exact unsupported `DeleteTaskDefinitions` signature, and an already-`INACTIVE` task definition are all required. Its ID, ARN, error code, and timestamp are persisted. The same response under `TARGET=aws` fails. Stale tags, retained cluster list entries, and endpoints in `deleted` are normal typed outcomes, not allowances. The former host-port plan-drift allowance is withdrawn because Fargate `awsvpc` port mappings now set equal host and container ports.

Each lease generation stores `cleanup_attempt`, `next_retry_at`, and `manual_intervention_required` through the same ETag compare-and-swap as status and manifest updates. Three automatic stage-1 executions are permitted. The third failure retains `cleanup_failed`, retains state, and requires manual intervention; a fourth automatic claim is refused. An operator may use the explicit `--force-retry` path after review, which appends a lease audit entry.

This amendment corrects three prior assumptions:

- The first implementation assumed successful Terraform destroy plus an empty tagged-VPC query was enough, and incorrectly allowed stage 1 to set `closed`.
- The full-inventory rework assumed the Tagging API would be empty immediately after destroy, so eventual-consistency records failed before exact checks ran.
- The first reconciliation rework assumed its ARN dispatcher was exhaustive and that any returned object was live, causing security-group-rule records to abort a batch and endpoints in `deleted` to be classified as live.

## Consequences

- An interrupted apply/destroy always leaves a lease the sweeper finishes, never a silently orphaned environment.
- The two-stage close adds latency, correct given async AWS deletion.
- Every taggable resource carries the env tag for discovery; exact service APIs and terminal-state predicates are the liveness source of truth.

## Alternatives considered

- **Terraform state alone as the record:** rejected — reflects only the last successful apply, not an in-progress transition.
- **DynamoDB lock table for leases:** rejected — a second persistent resource for what S3 ETag compare-and-swap already provides.
- **Single-stage close, longer timeout:** rejected — hosted jobs cap at 6 hours; task-definition deletion can take up to 24.

Live-proof findings 2026-09-02 (LocalStack 2026.8.1, after the typed-outcome redesign): (1) the `DeleteTaskDefinitions` allowance matched on the error code `NotImplementedException` from an invented fixture, while the emulator returns `InternalFailure` with the same message; the allowance now keys on the message signature and records the code, and that fixture is the one recorded backend response. (2) A stage-1 retry after a successful destroy tried to scale services that no longer exist; scale-to-zero now describes each service first and skips anything not ACTIVE or DRAINING. The remaining cleanup fixtures are authored from API or lifecycle contracts and are labeled `authored`, as documented in `tests/README.md`.

Plan-drift record 2026-09-02 (LocalStack 2026.8.1): after the explicit `hostPort` and the explicit `region` input to ecs-service (a module-level `depends_on` in the composition deferred the module's region data source to apply time and replaced the task definition on every plan; a cross-backend defect, fixed), a post-apply plan on LocalStack shows exactly one in-place change: `aws_lb_listener.http` port reads back as the emulator's edge port (4566) instead of 80. This is an emulator artifact, not a real-AWS behavior; it is not a cleanup allowance and CODE-ONLY until P0-3d.
