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
allowance, the 30-second AWS process boundary, tag-versus-manifest authority,
exact ECS `MISSING`/non-`MISSING`/unconfirmed-empty responses, the three-attempt
lease limit, audited force retry, generation-bound close refusal, and
end-to-end stage-1 state retention.

`tests/phase3-contracts.sh` separately checks the broader Phase 3 shell and
Makefile contracts. Neither suite starts, stops, or reconfigures LocalStack.
