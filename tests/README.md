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
boundary, tag-versus-manifest authority, a failed delayed tag observation,
zero-exit tag responses with a missing key, null list, string list, or empty
stdout, non-zero and malformed cleanup-verifier results,
exact ECS `MISSING`/non-`MISSING`/unconfirmed-empty responses, an absent state
file, required AWS destroy image references and their Terraform forwarding,
zero-exit `DeleteTaskDefinitions` responses that report the requested ARN in
their `failures` array,
the three-attempt lease limit, audited force retry, generation-bound close
refusal, and end-to-end stage-1 state retention.

`tests/phase3-contracts.sh` separately checks the broader Phase 3 shell and
Makefile contracts, including the LocalStack owner/rerun guards and the
signal-path test below. Neither suite starts, stops, or reconfigures
LocalStack.

Run the process-group signal test directly without LocalStack:

```
bash tests/localstack-concurrency-signal.sh
```

It replaces apply with a fake long-running pipeline, sends SIGTERM to the
concurrency script, and requires both the worker and its descendant to be
gone after the exit trap terminates and reaps the worker process group.

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
`scripts/aws-cli.sh`. Every record the post-close inventory still lists
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
in-progress and the second queued, then observe the destroy queued behind it.
After all runs are terminal, the test requires first-apply `updated_at` <=
second-apply `run_started_at` and second-apply `updated_at` <= destroy
`run_started_at`.

For LocalStack, both applies must conclude `success`; destroy must conclude
`failure` in `validate-input` with the exact `target=localstack` refusal. For
AWS, the first apply and the destroy must conclude `success` and the second
apply must conclude `failure`: per ADR 0006 the first apply leaves its lease
`open`, so the queued second apply is refused at lease open before any
resource is created. The AWS path always
reads the final lease through `TARGET=aws scripts/lease.sh` and requires
`closing` or `closed`; if destroy did not run last, the lease is `open`, or
final cleanup cannot be verified, it dispatches one recovery
`session-destroy` and fails with the reason. Neither target is a cross-run
lease test (each LocalStack run is a fresh emulator). Neither target cancels a
run unless `CANCEL_ON_EXIT=1` is explicitly set.

The session workflows execute jobs only on `main`. Supplying a non-main `REF`
is expected to create a skipped run, so it cannot satisfy this ordering test.
