# Shell contract tests

Run the cleanup regression suite without AWS or LocalStack:

```
bash tests/cleanup-verifier.sh
```

Sanitized JSON fixtures in `tests/fixtures/cleanup/` record candidate metadata
and exact API `rc`/`stdout`/`stderr` responses. The production predicate layer
consumes the same response shape for recorded and live probes. The suite covers
the 24-entry stale inventory incident, security-group-rule and unknown ARN
handling, VPC endpoint states, exact inactive ECS status, the scoped LocalStack
allowance, the 30-second AWS process boundary, tag-versus-manifest authority,
the three-attempt lease limit, audited force retry, and end-to-end stage-1 state
retention.

`tests/phase3-contracts.sh` separately checks the broader Phase 3 shell and
Makefile contracts. Neither suite starts, stops, or reconfigures LocalStack.
