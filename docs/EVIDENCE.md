# Evidence

This document collects every evidence claim made about orbit-infra: the labels used, the current evidence table, which PR checks must pass, and how the two backend targets (LocalStack and real AWS) relate to what has actually been run.

## Evidence labels

- **LOCALSTACK-VERIFIED** — ran against the LocalStack emulator, in CI or locally.
- **AWS-SIMULATED** — evaluated by the real-account IAM policy simulator; proves policy evaluation, not service enforcement.
- **CODE-ONLY** — implemented and contract-tested, but not yet executed on real AWS.
- **fixture-verified** — exercised through recorded fixtures rather than a live run.

## Evidence gates

LocalStack apply, Stage 1, and the successful in-job Stage 2 allowance/close path are LOCALSTACK-VERIFIED in CI (Phase 4 run 33757937265; post-merge dispatch run 33825140591 from main 9b253b6; stage-claim exclusivity, the pending hand-backs, and prune are fixture-verified only); the nightly AWS sweeper is CODE-ONLY behind P0-3b — the paid upgrade of the AWS account from the Free Plan, which the owner decided on 2026-09-08 not to pursue for this portfolio. The IAM policy simulator supplied real-account policy-evaluation evidence without applying the stack. Phase 5 IAM-matrix and recorded-demo evidence is summarized in the table below.

## Evidence table

Codes used below: `P0-3b` is the paid AWS account upgrade (the Free Plan cannot run the real bootstrap and service checks); `P0-3d` is the real-AWS promotion gate (apply bootstrap once, run the OIDC smoke workflow, then execute the remaining IAM matrix checks).

| Signal | Status |
|---|---|
| OIDC-federated Actions, no static AWS keys | in progress |
| Remote state, S3 native locking, bootstrapped once | in progress |
| Reusable modules + `terraform test` | in progress |
| Policy gates: tflint + checkov + conftest (public S3, open non-ALB ingress) on every PR plan; conftest also gates the saved AWS plan before apply | done (apply-side gate CODE-ONLY until P0-3d) |
| IAM action-condition matrix | 216 cases in 64 rows are `AWS-SIMULATED 2026-09-10 docs/assets/IAM_SIMULATION_REPORT.md`; rows containing an execution mismatch, live-call-only case, or not-simulatable case retain their lower label |
| IAM simulation report | `AWS-SIMULATED 2026-09-10 docs/assets/IAM_SIMULATION_REPORT.md`; 239 custom-policy cases (237 matched, 2 findings, 0 runner failures) and 156 role-policy cases (153 custom-lane agreements, 3 divergences); proves policy evaluation, not service enforcement |
| Recorded LocalStack demo | LOCALSTACK-VERIFIED recording; provenance and generator drift contract-verified in CI |
| Dispatch-only LocalStack CI apply → acceptance → Stage 1 | LOCALSTACK-VERIFIED in CI (Phase 4 run) |
| Canonical SBOM comparison + Trivy scan predicates + KMS-backed cosign signatures/attestations | CODE-ONLY until real-AWS publication and apply; offline canonicalization, ordering, and freshness contracts pass |
| In-job LocalStack Stage 2 | LOCALSTACK-VERIFIED in CI (run 33825140591) |
| AWS nightly sweeper | CODE-ONLY until P0-3b |
| Scheduled drift detection on persistent resources | planned |
| Cost guardrails: infracost PR comment + AWS Budgets alarm | infracost PR comment landed as a per-PR delta: 60 resources (17 estimated, 42 free, 1 unsupported); the AWS Budgets alarm waits for real AWS (P0-3b) |
| Observability: CloudWatch logs, two alarms, one written SLO | done |
| ADRs, runbooks, threat model | documents done; controls carry their own labels, mostly CODE-ONLY until P0-3d |

`P0-3d` remains the real-AWS promotion gate for an applied bootstrap, OIDC smoke, service-enforcement calls, and the cases the simulator cannot execute. The simulator has closed the policy-evaluation portion recorded above without applying the bootstrap.

## PR checks

Checks that must be green are `gates` on every PR and, on repository-owner-authored same-repository PRs, `plan-localstack` and `infracost`. The separate `oidc-smoke.yml` jobs skip fork PRs and runs whose `github.actor` is `dependabot[bot]`; their three `assume-*` jobs stay red on same-repository PRs because the three role-ARN secrets those jobs assume are real-account values that were never published (P0-3b, not planned).

## Two targets

Development runs against LocalStack, using the GitHub Student Developer Pack's LocalStack Student plan (Ultimate-tier service coverage), so the stack can be built and tested without AWS spend. The Phase 3 `terraform-plan` workflow has landed: static gates run on every pull request, while its secret-bearing LocalStack and Infracost jobs run only for the repository owner's own same-repository pull requests. Promotion to real AWS is not planned for this portfolio (decided 2026-09-08); the composition stays portable to it. Three things are verified only on real AWS: AWS Budgets (not emulated), ECS Exec, and exact OIDC trust-condition semantics. See ADR 0008. The three `assume-*` checks of `oidc-smoke.yml` fail on same-repository PRs until P0-3b (role secrets not yet published) and are skipped on fork PRs and on runs whose `github.actor` is `dependabot[bot]`; see RUNBOOKS "PR review gates".

## CI

`terraform-plan.yml` runs static gates on every pull request. Its LocalStack plan and Infracost comment jobs run only for the repository owner's own same-repository pull requests; no AWS credentials are involved. The Infracost GitHub App also reviews every pull request against FinOps policies as a separate `Infracost` check; `infracost.yml` pins its project list to `bootstrap` and `envs/preview` so the conftest fixture roots, deliberately insecure policy-gate inputs that are never deployed, are not evaluated.
