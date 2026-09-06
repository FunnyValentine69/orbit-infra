# STATE

```
LOCATION   Phase 5 built: P5-2 and P5-3 merged (PRs #10-#12); P5-4 complete (PR #13); P5-19 authored on feat/p5-19-iam-matrix (PR #15 open)
STATE      LocalStack apply, Stage 1, and the successful in-job Stage 2 allowance/close path are LOCALSTACK-VERIFIED in CI (Phase 4 run 33757937265; run 33825140591 from main 9b253b6); stage-claim exclusivity, the pending hand-backs, and prune are fixture-verified only; the IAM matrix has 85 statement rows and 13 binding rows with source and post-apply plan contracts, while every executable IAM case remains CODE-ONLY until P0-3d; the nightly AWS sweeper remains CODE-ONLY until P0-3b
NEXT       land PR #15 after Tier 3; decide P0-3b, which gates P5-1, P5-x, P5-5..P5-11, P5-22, P5-28, P5-29, and every CODE-ONLY IAM case; P5-12..P5-18, P5-20, P5-21 and P5-23..P5-31 otherwise remain open
```

Last verified: static gates PASS, sweeper 27 and cleanup verifier 48 fixture cases PASS, LocalStack sw5 cycle PASS at 0aef665, plan-localstack CI green, 2026-09-03; tools.lock versions verified 2026-09-02 via brew list --versions; conftest 0.69.0 via brew list --versions, gates all PASS incl. conftest 2026-09-04. Demo recorded 2026-09-05 with vhs 0.11.0 against LocalStack 2026.8.1 (docs/assets/DEMO_PROVENANCE.md). IAM matrix source/plan contracts and both policy-size contract groups PASS 2026-09-05.
