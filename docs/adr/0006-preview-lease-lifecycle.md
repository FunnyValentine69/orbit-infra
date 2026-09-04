# ADR 0006: Preview environment lease lifecycle

Status: Accepted (2026-09-02; amended 2026-09-03). Evidence gates: LocalStack apply, Stage 1, and the successful in-job Stage 2 allowance/close path are LOCALSTACK-VERIFIED in CI (Phase 4 run 33757937265; post-merge dispatch run 33825140591 from main 9b253b6; stage-claim exclusivity, the pending hand-backs, and prune are fixture-verified only); the nightly AWS sweeper is CODE-ONLY until P0-3b.

## Context

Environments are created/destroyed by independent CI dispatches that can be interrupted, retried, or overlap the nightly sweeper. Without a durable, race-safe state record, a crashed apply or overlapping destroy could orphan billable resources.

## Decision

Each `env_id` has a durable lease at `leases/<env_id>.json` with states `open → closing → closed | cleanup_failed` and a monotonically increasing `generation`. Every lease mutation is a compare-and-swap (S3 conditional write on one fresh-read ETag while asserting the operation's status, generation, and claim preconditions) — two writers can never both win. Apply order: runner-CIDR check → lint → checkov → verify every selected image signature and attestation against the lock files → create the lease only if absent or `closed` (generation N+1), with the workflow-run owner and initial target/mode/resolved-image manifest in that same CAS PUT → init → plan → apply; static and supply-chain gate failures never create a lease or resources, and there is no post-open manifest race. The apply workflow emits acquisition state and generation only after its CAS open succeeds, for summary reporting only. Its failure/cancellation handler does not depend on those step outputs: it reads the lease and invokes `close-env.sh` only when the lease is `open` or `closing` and its owner matches the current GitHub run ID and attempt. `close-env.sh --owner` independently refuses a mismatched owner with exit 4 before any transition; the generation guard remains independent. On AWS, close reuses the three resolved image references in the lease manifest so Terraform can load the configuration before destroy; a missing reference fails closed. The LocalStack lane continues to use its local defaults.

The session workflows accept `target=aws|localstack` and record the target in
the lease manifest. The AWS path retains the independent apply and destroy
dispatches. LocalStack state and the emulator live only on one hosted runner,
so `session-apply` performs the complete bootstrap → apply → acceptance →
Stage 1 → Stage 2 cycle in one job and closes its acquired generation only
after state-version removal. `session-destroy target=localstack` refuses with
a clear error because a fresh job has neither the emulator nor its state; it cannot prove cross-job
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

Close is two-stage since task definitions delete asynchronously (up to 24h) while a hosted job caps at 6. `begin-cleanup` CAS-acquires an exclusive `stage1_claim = {token, claimed_at}` while setting `closing`. Stage 1 carries that token on every manifest and failure transition while it discovers and scales ECS services, destroys with retries, requests task-definition deletion, and verifies every recorded candidate. A repeat Stage 1 and Stage 2 both refuse while the claim is active. Success clears the claim by CAS and leaves `closing` with Terraform state retained; failure clears it in the `cleanup_failed` transition, released by complete-stage1 or taken over only by an audited --force-retry run. Stage 1 never sets `closed`. Stage 2 then claims the exact unclaimed `closing` generation; once every task definition is deleted, it removes state versions and atomically appends its proof while setting `closed` and consuming its claim. The sweeper shares the `preview-<env_id>` concurrency group with apply/destroy so running jobs do not overlap. Both session workflows set `queue: max` (a documented GitHub Actions concurrency property since 2026-05-07, allowed only with `cancel-in-progress: false`) so every pending dispatch is retained and a queued destroy is never displaced; a review claim that the key is unsupported was refuted against the workflow-syntax reference and the changelog. The lease compare-and-swap, generation check, and retry-safe state machine are the correctness boundary; the workflow queue is only serialization. If a destroy is displaced while pending, the operator must re-dispatch it. `closed` leases prune after 7 days.

### Stage 2 sweeper amendment (2026-09-03)

`scripts/sweep.sh discover` reads JSON lines only from `lease.sh list`. It
classifies open leases older than 24 hours for Stage 1, due non-manual
`cleanup_failed` leases below the three-attempt budget for Stage 1 retry,
`closing` leases for Stage 2, and `closed` leases older than seven days for
prune. `sweep.sh env` always re-reads the lease and acts on that current state,
never on a discovery result. For Stage 1 it passes the generation and status it
classified to `close-env.sh`; `begin-cleanup` checks both again in its own fresh
read and CAS. The sweeper never supplies `--force-retry`.

For every `manifest.candidates[]` entry whose `resource_type` is
`ecs:task-definition`, Stage 2 calls `DescribeTaskDefinition` through the
repository AWS wrapper. Under `TARGET=aws`, deletion is proved only by this
exact AWS CLI error:

> An error occurred (ClientException) when calling the DescribeTaskDefinition operation: Unable to describe task definition.

This is intentionally narrower than the Stage 1 not-found matcher. The AWS
[task-definition state](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-definition-state.html)
and [DescribeTaskDefinition API](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_DescribeTaskDefinition.html)
contracts say `DELETE_IN_PROGRESS` remains retrievable and deletion can take
up to 24 hours, so `ACTIVE`, `INACTIVE`, and `DELETE_IN_PROGRESS` are pending
in Stage 2. A zero-exit response must contain the exact candidate ARN and a
recognized status; any other response is indeterminate and transitions
`closing → cleanup_failed`. The exact deleted response remains an authored
fixture until real-AWS promotion records it.

LocalStack has one additional deleted-by-allowance outcome: the candidate ARN
must already carry the Stage 1
`localstack-delete-task-definitions-inactive` allowance, the current describe
must return that exact ARN in `INACTIVE`, and `TARGET` must be `localstack`.
The sweeper records the allowance ID, ARN, and timestamp under
`manifest.stage2_allowances`; AWS never honors it.

Stage 2 obtains one exclusive `stage2_claim = {token, claimed_at}` only
when `stage1_claim` is null for the exact `closing` generation. Every Stage 2
manifest write requires that status, generation, and token. A pending task definition releases only that matching
claim by CAS so a later sweep can retry; successful completion has no separate
release. After every task definition is deleted or deleted-by-allowance, Stage
2 requires the last Stage 1 verification run to record `passed:true`, `live:0`,
and `indeterminate:0`. It does not repeat Stage 1's destroy-time probes. Stage
2 additionally requires zero pending results outside the manifest
task-definition ARN set; otherwise it releases its claim and hands the
`closing` lease back to Stage 1 for re-verification before any state deletion.
It paginates every version and delete marker for the exact
`envs/preview/<env_id>.tfstate` key, deletes them in batches of at most 1,000,
and performs a final empty-version read. A partial or indeterminate deletion
transitions to `cleanup_failed` and clears the matching claim. `closed` is
forbidden while any version remains. `complete-stage2` makes one fresh read and
one CAS that requires the status, generation, and claim, appends proof containing
`in_job`, `state_key`, deleted task-definition ARNs, and the verified-empty
timestamp to `manifest.stage2_runs`, sets `closed`, and consumes the claim.

Prune re-reads a `closed` lease older than seven days with its ETag and deletes
the current lease object with an `If-Match` precondition through `lease.sh`.
The nightly workflow is main-only and AWS-only. Discovery fails rather than
creating a matrix larger than 20; per-environment jobs use the shared
`preview-<env_id>` concurrency group, `queue: max`, `max-parallel: 3`, and do
not cancel sibling failures. LocalStack proves Stage 2 only in the same
`session-apply` job, using the emulator's versioned state bucket and identical
state-key layout; a second sweep over its new `closed` lease is a retention
no-op. LocalStack apply and Stage 1 are LOCALSTACK-VERIFIED in CI by the
Phase 4 run. The post-merge `session-apply` dispatch ran as run 33825140591
(main 9b253b6); in-job LocalStack Stage 2 is LOCALSTACK-VERIFIED in CI. The
nightly AWS sweeper is CODE-ONLY until P0-3b.

### Cleanup verifier amendment (2026-09-02)

The stage-1 candidate set is created before destroy and is the union of the prior manifest, identifiers from Terraform state, ECS discovery, and the pre-destroy tag inventory. Resource Groups Tagging API results are discovery evidence only. They are re-queried at 0, 2, 4, 8, 16, and 30 seconds after destroy and unioned into the candidate set, but neither a nonempty nor an empty tag response decides liveness. A tag query is successful only when its zero-exit stdout is a JSON object whose `ResourceTagMappingList` is an array and every member is an object with a string `ResourceARN` and, when present, an array `Tags`. Every other response is an indeterminate observation. An indeterminate pre-destroy observation or any indeterminate scheduled observation adds the unsupported `tag-inventory-incomplete` candidate; a later successful query cannot erase it, and verification cannot pass while the pre-destroy status is indeterminate.

One exact-resource verifier assigns one result to every candidate and persists every iteration:

- `gone`: absent, terminal, or non-billable under the resource-specific predicate. This includes VPC endpoints in `deleted`; ECS clusters/services in `INACTIVE`; ECS tasks in `STOPPED`; and task definitions in `INACTIVE` or `DELETE_IN_PROGRESS`. A successful ECS describe response with no matching cluster/service/task is `gone` only when every failure entry names the exact candidate ARN with reason `MISSING`; an empty collection with empty failures is indeterminate.
- `pending`: a recognized deletion transition, such as a VPC endpoint in `deleting`, or a secret with `DeletedDate` when force-delete semantics were not recorded.
- `live`: the exact API proves the resource remains usable or active.
- `indeterminate`: the exact probe timed out, was denied, returned malformed data, or has an unsupported resource type.

Stage 1 retries `pending`, post-destroy `live`, and transient `indeterminate` results for up to five minutes, with backoff capped at 30 seconds. Partial results are appended to `manifest.verification_runs` on every iteration. A non-zero verifier exit or malformed verifier result is routed through the same `cleanup_failed` lease transition with a recorded error. Before using a verifier result, close validates the outcome vocabulary, recomputes all four counts from `results`, requires the reported summary to match, and requires `passed` to equal the verifier rule (`live == 0 && indeterminate == 0`; pending is left for stage 2). If present, `stale_tag_entries` must be an array of objects. Any discrepancy records `cleanup_failed`, and close decisions use only the recomputed counts plus the validated `passed` value. At the deadline, `live` or `indeterminate` results set `cleanup_failed`; `pending` may remain for stage 2. Stale tag records whose exact probes are `gone` are persisted under `manifest.stale_tag_entries` and never fail stage 1.

All cleanup and lease AWS CLI calls pass through `scripts/aws-cli.sh`, with five-second connect and 20-second read timeouts inside a 30-second process-group deadline. The ECS service-stability waiter is the deliberate exception: it gets a 660-second outer deadline for the AWS CLI's ten-minute wait window. `TARGET` is mandatory. `localstack` requires an explicit localhost endpoint, test credentials, disabled metadata lookup, and no `AWS_PROFILE`; `aws` rejects a LocalStack endpoint.

The only stage-1 emulator allowance is `localstack-delete-task-definitions-inactive`: `TARGET=localstack`, the exact unsupported `DeleteTaskDefinitions` signature, and an already-`INACTIVE` task definition are all required. Its ID, ARN, error code, and timestamp are persisted. The same response under `TARGET=aws` fails. Stale tags, retained cluster list entries, and endpoints in `deleted` are normal typed outcomes, not allowances. The former host-port plan-drift allowance is withdrawn because Fargate `awsvpc` port mappings now set equal host and container ports.

Each lease generation stores `cleanup_attempt`, `next_retry_at`, and `manual_intervention_required` through the same ETag compare-and-swap as status and manifest updates. Three automatic stage-1 executions are permitted. The third failure retains `cleanup_failed`, retains state, and requires manual intervention; a fourth automatic claim is refused. An operator may use the explicit `--force-retry` path after review, which clears any active Stage 2 claim and appends that cleared claim to the lease audit entry.

The mutation interface is generation-bound. Each lease has
`stage1_claim` and `stage2_claim`, each null or `{token, claimed_at}`, and at
most one may be active. `begin-cleanup` requires `--generation`, the observed
`--from open|closing|cleanup_failed`, and `--claim`; its CAS installs the Stage
1 token. Stage-1 `set-manifest` and failure transitions require `closing`, the
generation, and that token. `complete-stage1` clears it by CAS. `claim-stage2`
requires an unclaimed `closing` lease, and `release-stage2` relinquishes only a
matching pending claim. Generic `transition` accepts only `cleanup_failed` and
clears the matching active claim. Only `complete-stage2` may produce `closed`,
in the same CAS that appends the Stage 2 proof and clears its claim.

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
