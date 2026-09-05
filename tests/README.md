# Shell contract tests

Evidence gates: LocalStack apply, Stage 1, and the successful in-job Stage 2 allowance/close path are LOCALSTACK-VERIFIED in CI (Phase 4 run 33757937265; post-merge dispatch run 33825140591 from main 9b253b6; stage-claim exclusivity, the pending hand-backs, and prune are fixture-verified only); the nightly AWS sweeper is CODE-ONLY until P0-3b.

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

The recorded Conftest plan sidecars carry their recording metadata in
`tests/fixtures/conftest/PROVENANCE.md`. A `terraform show -json` document
cannot carry a custom `recorded_from` key, so the recording metadata stays in
that sidecar.

## Phase 5 Conftest policy gate

Run the Conftest regression suite without AWS or LocalStack:

```
bash tests/conftest-gate.sh
```

The suite first runs fixture hygiene against both committed plans, then
requires `conftest verify` to pass all 85 Rego unit tests. It accepts the good
plan without reporting `aws_security_group.alb`, and requires the bad plan to
exit 1 and report `aws_s3_bucket.open`, `aws_s3_bucket.half`,
`aws_s3_bucket.data`, `aws_security_group.open`, `aws_security_group.alb`,
`aws_security_group.zero_lb`, `aws_vpc_security_group_ingress_rule.open`,
`aws_security_group_rule.legacy_open`, and
`aws_default_security_group.default`. It also requires the bad plan not to
report the protected `aws_s3_bucket.database`. The suite also proves that a
nested true `*_sensitive` marker and a sensitive output are rejected and
currently reports 17 cases. Bucket protection requires exactly one fully
locked planned block targeted through either one unambiguous whole-resource
configuration reference or an equal known planned bucket name. Reference and
planned-name correlations are unioned, distinct blocks targeting one bucket are
ambiguous, and unreferenced planned blocks with unknown or known-unmatched targets
are denied as unresolvable. Policy selectors accept only managed resources, so data-source
buckets are ignored and data-source load balancers cannot exempt a managed
group. Open, unknown, or prefix-list non-ALB ingress is denied because this
gate cannot prove a managed prefix list safe. Governed resources whose actions
contain `forget` are denied because their protections cannot be verified. For a
known ALB-group ID, a forgotten managed non-rule resource whose `change.before`
contains that ID also revokes the exemption; a fresh-created group has no known
pre-existing ID to match. The ALB exemption requires one distinct group
reference and a planned root application-ALB instance; known planned attachment
IDs must agree. A configuration group address correlates only when exactly one
planned group instance matches; multiple `count`/`for_each` instances fail
closed as ambiguous. Direct
configuration references from a network, gateway, unknown-type, or unplanned
`aws_lb`, other root managed resources, or root module calls revoke the
exemption, as does a matching known group ID anywhere in any managed planned
resource at any module depth. Planned application ALBs and rule-definition
resources are excluded from those consumer checks. Any configuration reference
under another security group's `expressions.ingress` or `expressions.egress`,
whether flattened or nested, is treated as a rule source; planned nested ingress
and egress `security_groups` source values are likewise excluded. Terraform plan
JSON does not serialize locals, so a
fresh-create ALB-group consumer hidden only behind local or other indirection
remains undetectable; this repository's own root attaches the ALB group only to
the ALB, which the live-plan gate checks through direct references.
An unknown attachment must reference exactly the group's whole-resource and
`.id` traversals. A standalone ingress
rule, including an indexed instance, must also plan a known target equal to the
group's known ID, or the rule target and group ID must both be unknown through
that same exact two-traversal set. Condition references and planned literal or
mismatched IDs are denied. Unknown legacy-rule direction is treated as
potentially ingress.

Fixture provenance: `good-plan.json` and `bad-plan.json` in
`tests/fixtures/conftest/` are `recorded_from` LocalStack 2026.8.1 with
Terraform 1.16.0 on 2026-09-04 from `good-root/` and `bad-root/` via
`make record-conftest-fixtures`. Each `terraform show -json` writes to a
temporary file; `scripts/fixture-hygiene.sh` must accept it before it replaces
the tracked fixture. The check rejects `prior_state`, true leaves below `*_sensitive` or
`sensitive_values`, objects marked `"sensitive": true`, non-empty top-level
`variables` because variables must not be serialized into fixtures,
non-placeholder 12-digit numbers, IPv4 literals outside
`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `0.0.0.0/0`, and
`127.0.0.1`, and email addresses. Fixtures are re-recorded
from those roots, never edited. The real `envs/preview` plan is never committed
because it can carry prior state and sensitive values.

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
same-environment second-open refusal, empty-`--from` refusal,
generation/status-bound Stage 1, exclusive Stage-1 and Stage-2 claims,
claim-bound manifest writes, duplicate-close refusal, generic-transition
refusal of `closed`, atomic proof-plus-close, force-cleared claim audit,
owner- and generation-bound close refusals, the three-attempt lease limit,
audited force retry, and end-to-end Stage-1 claim release with state retention.
The suite currently reports 48 cases.

`tests/phase3-contracts.sh` separately checks the broader Phase 3 shell and
Makefile contracts, including the LocalStack owner/rerun guards and the
signal-path test below. It also executes both the AWS close and LocalStack
close-and-sweep workflow blocks against controlled lease/close/sweep scripts
and verifies the observed generation, status, and owner arguments. It runs
`tests/dispatch-ordering-contracts.sh`, whose
jq-level probes extract the live jobs aggregation and timestamp-comparison
filters from `tests/dispatch-ordering.sh`. It also verifies that policy-size
remains required by default and moves to the owner-only `plan-localstack` job
after its health wait, and that Conftest is installed before the bootstrap-plan
gate, bootstrap apply, live plan, redacted summary, live-plan gate, and PR
comment in that order. Fork PRs receive the secret-free gates with policy-size
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
Stage-1 `passed:false` refusal, present-null version lists, malformed or
incomplete `delete-objects` acknowledgements, zero-exit per-object errors,
post-delete re-list refusal, partial deletion, a lease change between batches,
stale-open generation replacement before Stage 1, exclusive Stage 2 claim and
proof recording, an atomic-completion race that adds a new state version,
prune-time If-Match loss, and ETag-conditional prune. The suite currently
reports 27 cases.

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
  `delete-objects-errors.json`, `list-null-versions.json`,
  `delete-null-entry.json`, `delete-incomplete-ack.json`, and
  `aws-post-delete-relist.json` — `authored` fail-closed branch contracts;
  replace only from sanitized backend recordings that preserve the same
  condition.

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
