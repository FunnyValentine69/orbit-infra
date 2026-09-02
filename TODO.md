# TODO

- [x] P0-1 Install terraform, awscli, tflint, OrbStack
- [x] P0-2 Install scanners, signing tools, gitleaks, session-manager-plugin; write tools.lock
- [ ] P0-3 AWS account: Free Plan, IAM Identity Center user, SSO login, permission simulation (deferred: upgrade to Paid Plan when ready; Free Plan SCPs block the stack)
- [ ] P0-4 Create repo, skeleton, .gitignore, leak checks, secrets (in progress: secrets pending)
- [ ] P0-5 bootstrap/preflight.sh ownership discovery (in progress: written, not yet run)
- [ ] P0-6 bootstrap/ Terraform: state bucket, OIDC + 3 roles, KMS key, ECR repos, Budget (authored; apply deferred with P0-3)
- [ ] P0-7 Confirm Budgets notification email (deferred with P0-3)
- [ ] P0-8 oidc-smoke.yml role-assumption smoke workflow (written; run deferred with P0-3)

## Phase 1 — Repo docs + save-file

- [ ] P1-1 layout
- [x] P1-2 README
- [x] P1-3 ARCHITECTURE + ADRs 0001-0007
- [x] P1-4 STATE/TODO
- [x] P1-5 local CLAUDE.md (done)
- [x] P1-6 upstream.lock
- [x] P1-7 placeholder image

## Phase 2 — Modules + gates

- [x] P2-0 LocalStack lane: target variable, provider endpoints, make localstack-up/down, gitignore .localstack/ and volume/
- [x] P2-1 modules/network: VPC, two public AZs, one private subnet, no NAT, S3 gateway + 5 interface endpoints; mock tests; live LocalStack apply/destroy
- [x] P2-2 modules/ecs-service: ARM64 Fargate, exec, Cloud Map, optional ALB; preview cluster, namespace, service SG, api + gated worker
- [x] P2-3 modules/redis + modules/clickhouse; preview secret, data bucket, service wiring; uniform IAM naming; live S3 round-trip
- [x] P2-4 envs/preview composition: ALB with operator_cidr allowlist, per-environment S3 state keys, env-scoped LocalStack override; two concurrent environments verified
- [x] P2-5 policy gates: repo-wide .tflint.hcl + .checkov.yaml, make validate/lint/test, scripts/gates.sh
- [ ] P2-6 infracost breakdown and README cost line — deferred to P3-1 (runs in CI with the INFRACOST_API_KEY secret)
- [x] P2-7 narrow the deployer IAM statement in bootstrap/roles.tf to the exact actions the modules use; remove the five checkov skips there

## Phase 3 — CI/CD

(expanded when the phase starts)
- [x] P3-1 terraform-plan.yml: gates + LocalStack plan + sticky PR comment + gated infracost job; no AWS credentials (P2-6's cost line lands from the first CI run)
- [ ] P3-x: document that fork PRs skip oidc-smoke jobs (green-by-skip) in README/RUNBOOKS
- [x] P3-2: digest-pin the placeholder base image; write .github/workflows/mirror-images.yml (placeholder build/sign/attest + redis/clickhouse mirror with KMS signing, ADR 0007); needs real-AWS bootstrap + AWS_ROLE_PUBLISHER/AWS_KMS_SIGNING_KEY_ARN secrets before it can run
- [ ] P3-2b: hash-pin placeholder requirements (needs pip-tools; not installed this session)
- [x] P3-4: scripts/lease.sh (CAS lease on S3 ETag, ADR 0006) + scripts/close-env.sh (stage 1 of close) + session-apply.yml/session-destroy.yml (main-only, runner-CIDR check, lease open, plan/apply, negative ingress test) + Makefile lease-list/lease-get/close targets; live-verified on LocalStack (open/transition/CAS-race/list, full apply->close cycle)

## Phase 4 — Parallel environments + runbooks

(expanded when the phase starts)

## Phase 5 — Drift, sweeper, threat model, polish

(expanded when the phase starts)
