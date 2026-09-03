# STATE

```
LOCATION   Phase 3 is built; real-AWS contracts remain unmet until P0-3b/P3-3b and the deferred post-PR-#2-rebase plan/apply fixes land; PR #2 (Phase 2) in Tier 3; PR #3 (Phase 3) next
STATE      full preview stack (network, ALB, api, redis, clickhouse, secret, bucket) applies/destroys on LocalStack (default credentials; LocalStack does not enforce the deployer policy); deployer policy split into six managed policies with a task permissions boundary and tag-scoped mutation; two concurrent envs verified; lease.sh + two-stage close implementation present; session workflows validate env_id, pass locked private-ECR image digests, wait up to 10 minutes for every ECS service, assert runner ingress denial, and summarize the ALB URL; scripts/build-upstream.sh builds the three private upstream images from a locked-commit git archive and records bootstrap-qualified ECR digests after push; PUSH=1 + real-AWS signing remain deferred to P3-3b (needs P0-3b); SNS alerts topic + ALB alarms live-verified on LocalStack (alarms created, not evaluated)
BLOCKER    real-AWS acceptance requires P0-3b/P3-3b plus the deferred Makefile non-interactive saved-plan apply flow and terraform-plan.yml per-run plan path after rebasing PR #2
NEXT       merge PR #2, rebase feat/phase3-ci onto main, open PR #3
```

Last verified: tools.lock versions verified 2026-09-02 via brew list --versions.
