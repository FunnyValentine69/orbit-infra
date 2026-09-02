# orbit-infra

Ephemeral, near-zero-idle AWS platform for a containerized workload: Terraform, ECS Fargate (ARM64), GitHub Actions with OIDC (no static cloud keys), signed images, per-environment lease lifecycle.

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
| SBOM (syft) + Trivy scan + cosign keyless signing + GitHub attestations | planned |
| Dispatch-created parallel environments with nightly auto-destroy | planned |
| Scheduled drift detection on persistent resources | planned |
| Cost guardrails: infracost PR comment + AWS Budgets alarm | in progress |
| Observability: CloudWatch logs, one alarm, one written SLO | planned |
| ADRs, runbooks, threat model | in progress |

## Two targets

Development runs against LocalStack, using the GitHub Student
Developer Pack's LocalStack Student plan (Ultimate-tier service coverage),
so the stack can be built and tested without AWS spend. The terraform-plan
CI workflow (running Terraform plans on LocalStack, never holding AWS
credentials) lands with Phase 3; until then, gates run locally. Real
AWS is the promotion target once the platform is proven. Three things are
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
see RUNBOOKS.md to change it.

## Upstream

The reference workload is a private repository, `SuperGokou/happyCoding`,
used with its owner's permission. Its source and images are never
published; this repository deploys any image that satisfies the workload
contract (see ARCHITECTURE.md), and ships a public placeholder image so
the stack can be applied without the private upstream.

## Repository layout

```
bootstrap/          one-time Terraform: state bucket, OIDC + roles, KMS, ECR, Budget
placeholder/         public placeholder workload image
docs/adr/            architecture decision records
scripts/              repo hooks (pre-push guard, hook installer)
.github/workflows/    CI (oidc-smoke.yml today; more in later phases)
modules/              reusable Terraform modules (Phase 2+)
envs/                 per-environment composition (Phase 2+)
images/                workload image sources (Phase 2+)
```

## Gates

Local, pre-CI policy gates (`.tflint.hcl`, `.checkov.yaml` at repo root):

```
make validate     # terraform init -backend=false + validate, every module/env
make lint         # terraform fmt -check, tflint --recursive, checkov
make test         # terraform test, every module with a tests/ dir (also runs envs/*/tests)
scripts/gates.sh  # runs all four above (validate, lint, test, no-nat-gateway), PASS/FAIL summary; CI calls this from Phase 3 onward
```

`scripts/gates.sh` also runs the `policy-size` gate: it renders a LocalStack
plan of `bootstrap/` and requires every planned IAM policy document to be
plan-time known (see `bootstrap/README.md` § Gates / size). Run it standalone
with `bootstrap/policy-size-check.sh`.

CI: terraform-plan.yml runs the gates and a LocalStack plan on every pull
request; no AWS credentials are involved.

## Toolchain

Pinned tool versions and checksums: `tools.lock`.

## Status

See `STATE.md` for current phase and in-progress work.

## Documents

- `ARCHITECTURE.md` — system design and decisions
- `RUNBOOKS.md` — operational procedures
- `docs/adr/` — architecture decision records
