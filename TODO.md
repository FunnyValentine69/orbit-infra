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
- [ ] P2-6 infracost breakdown and README cost line — deferred to Phase 3 (terraform-plan.yml infracost job; runs in CI with the INFRACOST_API_KEY secret)
- [x] P2-7 narrow the deployer IAM statement in bootstrap/roles.tf to the exact actions the modules use; remove the five checkov skips there

## Phase 3 — CI/CD

(expanded when the phase starts)
- [ ] P3-x: document that fork PRs skip oidc-smoke jobs (green-by-skip) in README/RUNBOOKS
- [ ] P3-2: digest-pin the placeholder base image and add pip hash pinning (reproducible signed build)

## Phase 4 — Parallel environments + runbooks

(expanded when the phase starts)
- [ ] P4-x: ecs-service applies with wait_for_steady_state = false, so an apply exits 0 even if tasks never reach RUNNING; add a post-apply `aws ecs describe-services` steady-state check to the start-session runbook and session-apply.yml (Tier-1 P2 on PR #2)

## Phase 5 — Drift, sweeper, threat model, polish

(expanded when the phase starts)
- [ ] P5-x: per-workflow OIDC subject binding (verify the customized claim on a real token first)
- [ ] P5-5: `bootstrap/preflight.sh` runs `terraform init` (or detects an uninitialized backend) before `terraform state list`, so a fresh checkout that already has `backend.tf` is not treated as empty state (Tier-3 P2 on PR #1)
- [ ] P5-6: `bootstrap/preflight.sh` propagates `TF_VAR_oidc_provider_external=true` into the apply path when the OIDC provider already exists, instead of only printing the instruction (Tier-3 P2 on PR #1)
- [ ] P5-7: `oidc-smoke.yml` drops the plan-reader role secret from the `pull_request` job, since a same-repo PR can edit the workflow and print the ARN (Tier-3 P2 on PR #1)
- [ ] P5-8: exclude the bootstrap state key from the plan-reader read grant, or keep the budget email out of state, because sensitive variables are stored in plaintext state (Tier-3 P2 on PR #1)
