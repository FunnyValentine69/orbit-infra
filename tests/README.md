# Shell contract tests

Run the cleanup regression suite without AWS or LocalStack:

```
bash tests/cleanup-verifier.sh
```

Fixture provenance: a fixture with `recorded_from` was captured from a real
backend (currently LocalStack 2026.8.1 for the task-definition allowance); a
fixture marked `authored` was hand-written from an API or lifecycle contract
and must be replaced by a recorded response once that backend is available. Never
adjust an `authored` fixture to make a predicate pass; record the real
response instead.

Sanitized JSON fixtures in `tests/fixtures/cleanup/` record candidate metadata
and exact API `rc`/`stdout`/`stderr` responses. The production predicate layer
consumes the same response shape for recorded and live probes. The suite covers
the 24-entry stale inventory incident, security-group-rule and unknown ARN
handling, VPC endpoint states, exact inactive ECS status, the scoped LocalStack
allowance, the 30-second AWS process boundary and 660-second ECS waiter
boundary, tag-versus-manifest authority, failed delayed and pre-destroy-only tag
observations, zero-exit tag responses with a missing key, null list, string
list, empty stdout, entry missing `ResourceARN`, or numeric `ResourceARN`,
non-zero and malformed cleanup-verifier results, contradictory summaries,
invalid outcome strings, `passed:true` with a live result, and persistence of a
consistent `passed:false` live result before deadline failure, exact ECS
`MISSING`/non-`MISSING`/unconfirmed-empty responses, an absent state file,
required AWS destroy image references and their Terraform forwarding,
zero-exit `DeleteTaskDefinitions` responses that report the requested ARN in
their `failures` array, atomic owner-plus-manifest lease open with one PUT,
same-environment second-open refusal, owner- and generation-bound close
refusals, the three-attempt lease limit, audited force retry, and end-to-end
stage-1 state retention. The suite currently reports 41 cases.

`tests/phase3-contracts.sh` separately checks the broader Phase 3 shell and
Makefile contracts, including the LocalStack owner/rerun guards and the
signal-path test below. It runs `tests/dispatch-ordering-contracts.sh`, whose
jq-level probes extract the live jobs aggregation and timestamp-comparison
filters from `tests/dispatch-ordering.sh`. It also verifies that policy-size
remains required by default and moves to the owner-only `plan-localstack` job
after its health wait. Fork PRs receive the secret-free gates with policy-size
explicitly skipped; owner PRs receive those gates plus the LocalStack-backed
policy-size check. Neither suite starts, stops, or reconfigures LocalStack.

Run the process-group signal test directly without LocalStack:

```
bash tests/localstack-concurrency-signal.sh
```

It starts a fake worker whose process-group leader exits while a descendant
keeps running, sends SIGTERM to the concurrency script, and requires the
descendant to be gone after the exit trap targets the recorded process group
and reaps the recorded worker.

## Phase 5 sweeper fixtures

Run the Stage 2 regression suite without AWS or LocalStack:

```
bash tests/sweeper.sh
```

The suite reuses the repository AWS wrapper with a fake AWS CLI and a fake
versioned S3 lease/state store. It covers every discovery class and age
boundary, invalid inventory IDs, fresh-read Stage 1 selection, retry-budget
and manual-intervention refusal, exact AWS deleted `ClientException` versus
other non-zero describe errors, paginated/batched state-version and
delete-marker removal, `DELETE_IN_PROGRESS`, malformed describe/candidate
refusal, target-scoped LocalStack allowances and missing-allowance refusal,
Stage-1 `passed:false` refusal, zero-exit `delete-objects` errors, post-delete
re-list refusal, partial deletion, a lease change between delete batches,
closing-to-closed CAS loss, prune-time If-Match loss, and ETag-conditional
prune. The suite currently reports 21 cases.

Fixture provenance:

- `discover-cases.json` — `authored` from ADR 0006 lifecycle thresholds.
- `aws-deleted-client-exception.json` — `authored` from the AWS ECS deleted
  DescribeTaskDefinition contract; replace with a sanitized recording during
  real-AWS promotion.
- `aws-delete-in-progress.json` — `authored` from the AWS ECS
  `DELETE_IN_PROGRESS` contract.
- `aws-malformed-describe.json` — `authored` fail-closed schema case.
- `localstack-inactive-allowance.json` — `authored` Stage 2 response paired
  with the Stage 1 allowance recorded from LocalStack 2026.8.1; the
  orchestrator replaces it only from a sanitized in-job recording.
- `aws-clientexception-mismatch.json`,
  `aws-inactive-with-localstack-allowance.json`,
  `localstack-inactive-no-allowance.json`, `aws-verification-failed.json`,
  `delete-objects-errors.json`, and `aws-post-delete-relist.json` — `authored`
  fail-closed branch contracts; replace only from sanitized backend recordings
  that preserve the same condition.

## Phase 4 live concurrency

With one already-running LocalStack, an applied LocalStack bootstrap, and the
ARM64 placeholder image present, run:

```
make test-concurrency TARGET=localstack OPERATOR_CIDR=10.255.255.255/32
```

`tests/localstack-concurrency.sh` generates a distinctive `cca...1`/`cca...2`
pair unless `ENV_A` and `ENV_B` are supplied. On that one emulator it proves
lease open/closing refusals and generation stability, overlaps both applies
and both generation-bound closes, checks the isolated `.preview-runs/<id>`
states and ECS cluster names, and queries the module `env_id` tag through
`scripts/aws-cli.sh`. The two filtered ARN sets must be disjoint, and every
returned record must carry exactly one `env_id` tag matching the requested
environment; the ARN text cross-reference check remains an additional guard.
Every record the post-close inventory still lists
(the tagging API is eventually consistent, and LocalStack retains entries for
deleted resources) is evaluated by `scripts/cleanup-verifier.sh` exact probes,
which must report zero live, indeterminate, or pending; the test does not
duplicate the verifier's LocalStack allowance or exact-resource predicates.
Its exit trap closes every lease generation it acquired. Before starting
those closes, the trap terminates
each active apply/close process group and reaps every worker; a failed run
retains only redacted diagnostics.

This local, single-emulator run is the lease-semantics proof. Each hosted
LocalStack workflow run gets a fresh runner and fresh emulator, so separate
GitHub runs cannot observe one another's lease, state, CAS refusal, or
generation increment.

## Phase 4 dispatch ordering

After the change is on `main`, run the LocalStack queue test with:

```
ENV_ID=ord1 TARGET=localstack REF=main bash tests/dispatch-ordering.sh
```

Each invocation generates a nonce, passes a distinct nonce-bearing
`dispatch_note` to all three workflows, and captures exactly one new run whose
display title contains that note, event is `workflow_dispatch`, and head branch
equals `REF`. Both targets require three queue polls with the first apply
in-progress and the second held (`pending`, GitHub's status for a run blocked
by its concurrency group, or `queued`), then observe the destroy held behind it.
After all runs are terminal, the test requires the first apply's latest job
`completed_at` < the second apply's earliest job `started_at`, and the second
apply's latest job `completed_at` < the destroy's earliest job `started_at`.
Equal timestamps are inconclusive and fail closed.
Job timestamps are used because GitHub stamps a run's `run_started_at` when
it accepts the dispatch, before the concurrency group releases the run.
Skipped jobs (for example the destroy job behind a refused validate-input)
are excluded from the aggregation. Before aggregating, each jobs response must
have `total_count` equal to the returned jobs-array length, at least one
non-skipped job, and string `started_at` and `completed_at` values on every
non-skipped job. A response that fails any condition is treated as lagging and
the jobs endpoint is read up to three times ten seconds apart before failing
closed with the condition that remained unsatisfied.

For LocalStack, both applies must conclude `success`; destroy must conclude
`failure` in `validate-input` with the exact `target=localstack` refusal. For
AWS, the first apply and the destroy must conclude `success` and the second
apply must conclude `failure`: per ADR 0006 the first apply leaves its lease
`open`, so the queued second apply is refused at lease open before any
resource is created. The AWS path always
reads the final lease through `TARGET=aws scripts/lease.sh` and requires
the destroy conclusion to be `success` before treating `closing` or `closed`
as safe. Any non-success destroy conclusion, an `open` or `cleanup_failed` lease, an
unreadable status, or invalid ordering leaves cleanup unchecked so the EXIT
trap dispatches one recovery `session-destroy`; the failure names the destroy
run id and observed lease status. Neither target is a cross-run
lease test (each LocalStack run is a fresh emulator). Neither target cancels a
run unless `CANCEL_ON_EXIT=1` is explicitly set.

The session workflows execute jobs only on `main`. Supplying a non-main `REF`
is expected to create a skipped run, so it cannot satisfy this ordering test.
