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
- [ ] P2-4 also: narrow the deployer IAM statement to the exact actions the modules use; remove the five checkov skips in bootstrap/roles.tf

## Phase 3 — CI/CD

(expanded when the phase starts)
- [ ] P3-x: document that fork PRs skip oidc-smoke jobs (green-by-skip) in README/RUNBOOKS

## Phase 4 — Parallel environments + runbooks

(expanded when the phase starts)

## Phase 5 — Drift, sweeper, threat model, polish

(expanded when the phase starts)
