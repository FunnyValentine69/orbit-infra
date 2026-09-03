# orbit-infra

Ephemeral, near-zero-idle AWS platform for a containerized workload: Terraform, ECS Fargate (ARM64), GitHub Actions with OIDC (no static cloud keys), signed images, per-environment lease lifecycle.

Evidence: LOCALSTACK-VERIFIED for apply/close on LocalStack; every real-AWS behavior in this document is CODE-ONLY until the promotion gate P0-3d runs.

## What this is

An ephemeral, near-zero-idle AWS platform: every environment is created and
destroyed on demand by a lease-managed lifecycle, so nothing runs (and
almost nothing costs money: one KMS key at about a dollar a month) when no one is using it. It is workload-agnostic — the
platform, not any one application, is the deliverable. All CI/CD runs
through GitHub Actions federated with AWS via OIDC; no static cloud keys
exist anywhere in the pipeline.

## Senior-signal checklist

| Signal | Status |
|---|---|
| OIDC-federated Actions, no static AWS keys | in progress |
| Remote state, S3 native locking, bootstrapped once | in progress |
| Reusable modules + `terraform test` | in progress |
| Policy gates: tflint + checkov on every plan | done |
| Dispatch-only LocalStack CI apply → acceptance → close cycle | implemented, CODE-ONLY until first dispatch |
| SBOM (syft) + Trivy scan + KMS-backed cosign signatures/attestations | in progress |
| Dispatch-created parallel environments with nightly auto-destroy | planned |
| Scheduled drift detection on persistent resources | planned |
| Cost guardrails: infracost PR comment + AWS Budgets alarm | in progress |
| Observability: CloudWatch logs, two alarms, one written SLO | done |
| ADRs, runbooks, threat model | in progress |

## Two targets

Development runs against LocalStack, using the GitHub Student
Developer Pack's LocalStack Student plan (Ultimate-tier service coverage),
so the stack can be built and tested without AWS spend. The Phase 3
`terraform-plan` workflow has landed: static gates run on every pull request,
while its secret-bearing LocalStack and Infracost jobs run only for the
repository owner's own same-repository pull requests. Real AWS is the promotion
target once the platform is proven. Three things are
verified only on real AWS: AWS Budgets (not emulated), ECS Exec, and exact
OIDC trust-condition semantics. See ADR 0008.

## Quickstart (LocalStack)

```
make localstack-up
make plan TARGET=localstack ENV_ID=dev
make apply TARGET=localstack ENV_ID=dev
make destroy TARGET=localstack ENV_ID=dev
```

## Quickstart (AWS)

See `bootstrap/README.md` for the one-time bootstrap apply sequence. The
ALB ingress allowlist is read from the `OPERATOR_CIDR` repository secret;
see RUNBOOKS.md to change it. Preview workflows generate the required AWS
backend config from bootstrap naming, save the plan, and apply that exact plan
non-interactively.

## Upstream

The reference workload is a private repository, `SuperGokou/happyCoding`,
used with its owner's permission. Its source and images are never publicly
published; this repository deploys any image that satisfies the workload
contract (see ARCHITECTURE.md), and ships a public-source placeholder image
through private ECR so the stack can be applied without the private upstream.

`session-apply` requires an explicit deployment mode. `upstream` selects the
locked `orbit-api` and `orbit-clickhouse` images plus mirrored Redis. `public`
selects the locked private-ECR placeholder plus mirrored Redis and ClickHouse.
The workflow opens no lease until every repository name matches
`bootstrap/ecr.tf`, every selected lock entry is digest-pinned, and every image
has a valid signature and lock-matching attestation. The opened lease records
the mode and resolved image references so AWS cleanup can load the same
Terraform configuration for destroy.

## Repository layout

```
bootstrap/          one-time Terraform: state bucket, OIDC + roles, KMS, ECR, Budget
placeholder/         public-source placeholder workload image
docs/adr/            architecture decision records
scripts/              repo hooks (pre-push guard, hook installer)
tests/                shell-level lifecycle and CI contracts
.github/workflows/    CI (oidc-smoke.yml today; more in later phases)
modules/              reusable Terraform modules (Phase 2+)
envs/                 per-environment composition (Phase 2+)
images/                workload image sources (Phase 2+)
upstream.lock           private upstream build inputs and pushed ECR digests
mirror-images.lock      placeholder plus Redis/ClickHouse private-ECR digests
```

## Gates

Local, pre-CI policy gates (`.tflint.hcl`, `.checkov.yaml` at repo root):

```
make validate     # terraform init -backend=false + validate, every module/env
make lint         # terraform fmt -check, tflint --recursive, checkov
make test         # terraform test, every module with a tests/ dir (also runs envs/*/tests)
make test-concurrency TARGET=localstack OPERATOR_CIDR=10.255.255.255/32  # two live environments on one already-running emulator
scripts/gates.sh  # runs all four above (validate, lint, test, no-nat-gateway), PASS/FAIL summary; CI calls this from Phase 3 onward
```

The live concurrency target, its LocalStack-free SIGTERM/process-group test,
and the nonce-bound post-merge GitHub dispatch-ordering test are documented in
`tests/README.md`; none starts, stops, or reconfigures LocalStack.

`scripts/gates.sh` also runs the `policy-size` gate: it renders a LocalStack
plan of `bootstrap/` and requires every planned IAM policy document to be
plan-time known (see `bootstrap/README.md` § Gates / size). Run it standalone
with `bootstrap/policy-size-check.sh`.

CI: `terraform-plan.yml` runs static gates on every pull request. Its
LocalStack plan and Infracost comment jobs run only for the repository owner's
own same-repository pull requests; no AWS credentials are involved.

## Toolchain

Pinned tool versions and checksums: `tools.lock`.

## Status

See `STATE.md` for current phase and in-progress work.

## Documents

- `ARCHITECTURE.md` — system design and decisions
- `RUNBOOKS.md` — operational procedures
- `docs/adr/` — architecture decision records
