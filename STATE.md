# STATE

```
LOCATION   Phase 5 in progress: P5-2, P5-3, P5-4, P5-19 and P5-27 complete (PRs #10-#16); P5-32 in this PR
STATE      LocalStack apply, Stage 1, and the successful in-job Stage 2 allowance/close path are LOCALSTACK-VERIFIED in CI (Phase 4 run 33757937265; run 33825140591 from main 9b253b6); stage-claim exclusivity, the pending hand-backs, and prune are fixture-verified only; the IAM matrix has 85 statement rows and 13 binding rows with source and post-apply plan contracts, while every executable IAM case remains CODE-ONLY until P0-3d; the nightly AWS sweeper remains CODE-ONLY until P0-3b
NEXT       decide P0-3b, which gates P5-1, P5-x, P5-5..P5-11, P5-22, P5-28, P5-29, and every CODE-ONLY IAM case; then P5-24..P5-26, lease batch P5-12..P5-18, P5-20/21/23, and P5-28..P5-31
```

Last verified: static gates PASS, sweeper 27 and cleanup verifier 48 fixture cases PASS, LocalStack sw5 cycle PASS at 0aef665, plan-localstack CI green, 2026-09-03; tools.lock versions verified 2026-09-02 via brew list --versions; conftest 0.69.0 via brew list --versions, gates all PASS incl. conftest 2026-09-04. IAM matrix source/plan contracts and both policy-size contract groups PASS 2026-09-05. Demo recorded 2026-09-06 by the transactional recorder; the contract suite, make test, and gates PASS with no expected failure, and the declared generator paths are unchanged between the provenance generator commit and HEAD.
