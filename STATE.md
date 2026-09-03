# STATE

```
LOCATION   Phase 3 complete except P3-3b (real-AWS push, with P0-3b); PR #2 (Phase 2) in Tier 3; PR #3 (Phase 3) next
STATE      full preview stack (network, ALB, api, redis, clickhouse, secret, bucket) applies/destroys on LocalStack (default credentials; LocalStack does not enforce the deployer policy); deployer policy split into six managed policies with a task permissions boundary and tag-scoped mutation; two concurrent envs verified; lease.sh + close-env.sh live-verified (open/transition/CAS-race/list, full apply->close cycle) on LocalStack; session-apply.yml/session-destroy.yml written (real-AWS run deferred, needs AWS_ROLE_DEPLOYER + OPERATOR_CIDR secrets); scripts/build-upstream.sh builds orbit-api/orbit-worker/orbit-clickhouse locally from a locked-commit git archive, live-verified (13 ClickHouse tables, fastapi import) with three passing negative tests; PUSH=1 + sign-images.yml deferred to P3-3b (needs P0-3b); SNS alerts topic + ALB alarms live-verified on LocalStack (alarms created, not evaluated)
BLOCKER    none (real-AWS apply deferred with P0-3b)
NEXT       merge PR #2, rebase feat/phase3-ci onto main, open PR #3
```

Last verified: tools.lock versions verified 2026-09-02 via brew list --versions.
