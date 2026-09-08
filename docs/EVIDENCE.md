# Evidence

This document collects every evidence claim made about orbit-infra: the labels used, the current evidence table, which PR checks must pass, and how the two backend targets (LocalStack and real AWS) relate to what has actually been run.

## Evidence labels

- **LOCALSTACK-VERIFIED** — ran against the LocalStack emulator, in CI or locally.
- **CODE-ONLY** — implemented and contract-tested, but not yet executed on real AWS.
- **fixture-verified** — exercised through recorded fixtures rather than a live run.

## Evidence gates

LocalStack apply, Stage 1, and the successful in-job Stage 2 allowance/close path are LOCALSTACK-VERIFIED in CI (Phase 4 run 33757937265; post-merge dispatch run 33825140591 from main 9b253b6; stage-claim exclusivity, the pending hand-backs, and prune are fixture-verified only); the nightly AWS sweeper is CODE-ONLY until P0-3b — the deferred upgrade of the AWS account from the Free Plan to the Paid Plan, which every item labeled "until P0-3b" waits on. Phase 5 IAM-matrix and recorded-demo evidence is summarized in the table below.

## Evidence table

Codes used below: `P0-3b` is the paid AWS account upgrade (the Free Plan cannot run the real-AWS checks); `P0-3d` is the real-AWS promotion gate (apply bootstrap once, run the OIDC smoke workflow, then execute the IAM matrix cases).

| Signal | Status |
|---|---|
| OIDC-federated Actions, no static AWS keys | in progress |
| Remote state, S3 native locking, bootstrapped once | in progress |
| Reusable modules + `terraform test` | in progress |
| Policy gates: tflint + checkov + conftest (public S3, open non-ALB ingress) on every PR plan; conftest also gates the saved AWS plan before apply | done (apply-side gate CODE-ONLY until P0-3d) |
| IAM action-condition matrix | source and post-apply plan contracts; executable cases CODE-ONLY until P0-3d |
| Recorded LocalStack demo | LOCALSTACK-VERIFIED recording; provenance and generator drift contract-verified in CI |
| Dispatch-only LocalStack CI apply → acceptance → Stage 1 | LOCALSTACK-VERIFIED in CI (Phase 4 run) |
| Canonical SBOM comparison + Trivy scan predicates + KMS-backed cosign signatures/attestations | CODE-ONLY until real-AWS publication and apply; offline canonicalization, ordering, and freshness contracts pass |
| In-job LocalStack Stage 2 | LOCALSTACK-VERIFIED in CI (run 33825140591) |
| AWS nightly sweeper | CODE-ONLY until P0-3b |
| Scheduled drift detection on persistent resources | planned |
| Cost guardrails: infracost PR comment + AWS Budgets alarm | infracost PR comment landed as a per-PR delta: 60 resources (17 estimated, 42 free, 1 unsupported); the AWS Budgets alarm waits for real AWS (P0-3b) |
| Observability: CloudWatch logs, two alarms, one written SLO | done |
| ADRs, runbooks, threat model | documents done; controls carry their own labels, mostly CODE-ONLY until P0-3d |

`P0-3d` is the real-AWS promotion gate: applying bootstrap, running OIDC smoke, then executing `docs/iam-matrix.md` as the per-principal positive/negative API specification, before any preview apply.

## PR checks

Checks that must be green are `gates` on every PR and, on repository-owner-authored same-repository PRs, `plan-localstack` and `infracost`. The separate `oidc-smoke.yml` jobs skip fork PRs and runs whose `github.actor` is `dependabot[bot]`; their three `assume-*` jobs stay red on same-repository PRs until the paid account upgrade (P0-3b), because the role-ARN and KMS secrets those jobs assume are not yet published.

## Two targets

Development runs against LocalStack, using the GitHub Student Developer Pack's LocalStack Student plan (Ultimate-tier service coverage), so the stack can be built and tested without AWS spend. The Phase 3 `terraform-plan` workflow has landed: static gates run on every pull request, while its secret-bearing LocalStack and Infracost jobs run only for the repository owner's own same-repository pull requests. Real AWS is the promotion target once the platform is proven. Three things are verified only on real AWS: AWS Budgets (not emulated), ECS Exec, and exact OIDC trust-condition semantics. See ADR 0008. The three `assume-*` checks of `oidc-smoke.yml` fail on same-repository PRs until P0-3b (role secrets not yet published) and are skipped on fork PRs and on runs whose `github.actor` is `dependabot[bot]`; see RUNBOOKS "PR review gates".

## CI

`terraform-plan.yml` runs static gates on every pull request. Its LocalStack plan and Infracost comment jobs run only for the repository owner's own same-repository pull requests; no AWS credentials are involved. The Infracost GitHub App also reviews every pull request against FinOps policies as a separate `Infracost` check; `infracost.yml` pins its project list to `bootstrap` and `envs/preview` so the conftest fixture roots, deliberately insecure policy-gate inputs that are never deployed, are not evaluated.
