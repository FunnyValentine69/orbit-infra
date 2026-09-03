# TODO

- [x] P0-1 Install terraform, awscli, tflint, OrbStack
- [x] P0-2 Install scanners, signing tools, gitleaks, session-manager-plugin; write tools.lock
- [ ] P0-3 AWS account: Free Plan, IAM Identity Center user, SSO login, permission simulation (deferred: upgrade to Paid Plan when ready; Free Plan SCPs block the stack)
- [ ] P0-4 Create repo, skeleton, .gitignore, leak checks, secrets (in progress: secrets pending)
- [ ] P0-5 bootstrap/preflight.sh ownership discovery (in progress: written, not yet run)
- [ ] P0-6 bootstrap/ Terraform: state bucket, OIDC + 3 roles, KMS key, ECR repos, Budget (authored; apply deferred with P0-3)
- [ ] P0-7 Confirm Budgets notification email (deferred with P0-3)
- [ ] P0-8 oidc-smoke.yml role-assumption smoke workflow (written; run deferred with P0-3)
- [x] P0-3c: add `redis_image` and `clickhouse_image` passthrough variables so real-AWS sessions use the locked private-ECR mirror digests
- [ ] P0-3f: PR #5 Tier 3 overflow (bot pass 3 on aa2cf29, recorded under the one-fix-round cap; both are real-AWS-only paths, CODE-ONLY until P0-3b):
  - P1 tests/dispatch-ordering.sh, the `dispatch_and_capture session-destroy.yml "destroy"` call (search for it; line numbers drift): with `TARGET=aws` and an `ENV_ID` whose lease is already `open`, both test applies are refused by the lease CAS but the destroy still queues and tears down the pre-existing environment (session-destroy has no owner binding). Fix: before dispatching, read the lease with `TARGET=aws scripts/lease.sh get` and refuse unless it is absent or `closed`; or bind the destroy to the generation and owner the captured first apply created.
  - P2 bootstrap/kms.tf ~28: the key policy names the publisher role through `local.publisher_role_arn` (plan-time-known by design, no dependency edge), so a fresh real-AWS bootstrap may call CreateKey before the role exists and KMS rejects the invalid principal. Fix: `depends_on = [aws_iam_role.publisher]` on `aws_kms_key.signing`, keeping the document plan-time-known.
- [x] P0-3e: Tier 3 overflow from PR #4 — CODE-ONLY until executed: session-apply cleanup runs on cancelled() as well as failure() once the lease is acquired; mirror-images scans each mirror before signing/attesting; close-env inspects delete-task-definitions response failures for the requested ARN; the runner-CIDR check runs in the same job as the apply
- [ ] P0-3d: real-AWS promotion gate: apply bootstrap only, OIDC smoke, then per-principal positive/negative API matrix across the ten policy documents including the task boundary as a cap, before any preview apply (CODE-ONLY until then)

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
- [x] P2-7 narrow the deployer IAM statement in bootstrap/roles.tf: the policy covers the Phase 2 module actions plus the Phase 3 alarm resources (SNS topic and subscription, CloudWatch alarms) that are pre-provisioned on this branch by decision; remove the five checkov skips there

## Phase 3 — CI/CD

(expanded when the phase starts)
- [x] P3-1 terraform-plan.yml: gates + LocalStack plan + sticky PR comment + gated infracost job; no AWS credentials (P2-6's cost line lands from the first CI run)
- [ ] P3-x: document that fork PRs skip oidc-smoke jobs (green-by-skip) in README/RUNBOOKS
- [x] P3-2: digest-pin the placeholder base image; write .github/workflows/mirror-images.yml (placeholder build/sign/attest + redis/clickhouse mirror with KMS signing, ADR 0007); needs real-AWS bootstrap + AWS_ROLE_PUBLISHER/AWS_KMS_SIGNING_KEY_ARN secrets before it can run
- [ ] P3-2b: hash-pin placeholder requirements (needs pip-tools; not installed this session)
- [x] P3-3: scripts/build-upstream.sh (locked-commit `git archive`-only local build of orbit-api/orbit-worker/orbit-clickhouse, three negative tests verified) + images/clickhouse/Dockerfile (named `upstream` build context) + .github/workflows/sign-images.yml (KMS signing/attestation of already-pushed images); upstream.lock records upstream_archive_sha256, repo_build_inputs_sha256, and local_id per image
- [x] P3-14: stage-1 close redesign (typed outcomes, monotonic indeterminate tag evidence, recomputed verifier summaries and `passed`, strict tagging/verifier response schemas, AWS CLI wrapper with timeouts, LocalStack allowances in the manifest, three-attempt retry budget, atomic owner-plus-manifest lease open, owner-bound cancellation close) LOCALSTACK-VERIFIED for the earlier live path (see ADR 0006, "Live-proof findings 2026-09-02"); fixture suite tests/cleanup-verifier.sh (40 cases; one recorded backend response, remaining fixtures authored)
- [ ] P3-3b: push the three images with PUSH=1 after P0-3b, then dispatch sign-images.yml
- [x] P3-6: AWS `make plan` saves a plan and `make apply` non-interactively consumes that exact plan; session workflows generate the required backend config from bootstrap naming
- [x] P3-13: terraform-plan.yml reads and removes the LocalStack plan from the per-environment `PREVIEW_ROOT` run directory
- [x] P3-4: scripts/lease.sh (CAS lease on S3 ETag, ADR 0006) + scripts/close-env.sh (stage 1 of close) + session-apply.yml/session-destroy.yml (main-only, runner-CIDR check, lease open, plan/apply, negative ingress test) + Makefile lease-list/lease-get/close targets; live-verified on LocalStack (open/transition/CAS-race/list, full apply->close cycle)
- [x] P3-5: SNS alerts topic (optional email subscription via var.alert_email) + UnHealthyHostCount and HTTPCode_Target_5XX_Count CloudWatch alarms on the ALB target group; SLO documented in ARCHITECTURE.md; live-verified on LocalStack (alarms created, not evaluated)

## Phase 4 — Parallel environments + runbooks (Option A, 2026-09-03)

- [x] P4-ci: PR #5's `terraform-plan.yml` gates job failed in its first step on every PR since Phase 3 (also feat/phase3 runs): tools.lock lists each tool in a versions and a checksums section, so `grep '^terraform ' | awk` printed two lines and GITHUB_OUTPUT rejected the record (`Invalid format '<checksum'`); all eleven workflow version reads now go through `scripts/tool-version.sh` (exactly one semantic version or a hard error) with a phase3 contract forbidding grep/awk on tools.lock — CI-VERIFIED 2026-09-03: PR #5 run 33756687931 gates, plan-localstack (with policy-size), and infracost all green
- [x] P4-review: PR #5 Tier 1 (Sonnet roster, deep) two P1 fixed, one refuted; Tier 2 (Codex xhigh) two iterations, 3 P1 + 3 P2 then 4 P1, all fixed by Codex (triggering_actor rerun guard, dispatch-ordering chain and nonce-bound capture, malformed tagging/verifier responses fail closed, process-group reaping, atomic owner-plus-manifest lease open, owner-bound cancel close); Tier 2 iteration cap reached, so the iteration-2 fixes are reviewed by Tier 3 — LOCALSTACK-VERIFIED locally: `make test-concurrency` on the final close path and a single workflow-body cycle (env p4w) with owner-bound close
- [x] P4-0: land P0-3e overflow fixes — CODE-ONLY until the affected workflows execute; cleanup fixture suite passes locally
- [x] P4-4: `target=localstack` mode for session-apply.yml and session-destroy.yml: owner-only setup-localstack lane, in-job bootstrap, ARM64 placeholder build, public image defaults, no AWS role assumption, same lease/acceptance path, and same-job stage-1 close; destroy refuses cross-job LocalStack use — the workflow's own gate, probe, and close step bodies are LOCALSTACK-VERIFIED locally (env p4v, 2026-09-03: 3 services on applied task definitions, probe curl exit 7, 59 destroyed, lease closing); the CI lane is LOCALSTACK-VERIFIED in CI 2026-09-03 (run 33757937265 from main, env p4ci: bootstrap 35 resources on the runner, owner-bound lease open, 59 resources applied, 3 services on their applied task definitions, runner probe curl exit 7, 59 destroyed, lease left closing; apply job 9m50s)
- [x] P4-1: repeatable concurrency script `tests/localstack-concurrency.sh` (two environments apply/close concurrently, independent state and leases, process-group termination/reaping before trap cleanup) — LOCALSTACK-VERIFIED locally 2026-09-03 (`make test-concurrency`: environments=2, state_resources=126, tagged_resources=60, residual_inventory_entries=44 all classified gone by the verifier's exact probes, lease_refusals=4); the SIGTERM path is fixture-verified without LocalStack; the CI-mode execution stays CODE-ONLY until the first main-only dispatch
- [x] P4-2: nonce-bound three-dispatch ordering test `tests/dispatch-ordering.sh` (unique run capture, complete terminal/start chain, target-specific conclusions, unconditional AWS final-lease verification with recovery dispatch) and the exact post-merge PR-comment commands — first live run from main 2026-09-03 exposed a test defect (GitHub reports a concurrency-held run as `pending`, not `queued`; fixed here); a second live defect: GitHub stamps `run_started_at` at dispatch acceptance, so the chain now uses job timestamps — LOCALSTACK-VERIFIED in CI 2026-09-03 (`ENV_ID=ord1 TARGET=localstack REF=main bash tests/dispatch-ordering.sh` PASS: runs 33777429831 → 33777442148 → 33777566273; second apply held `pending` for three 20 s polls, destroy held behind it, jobs 16:14:30–16:24:03 / 16:24:06–16:33:25 / 16:33:28–16:33:33, destroy refused in validate-input as designed)
- [x] P4-3: numbered RUNBOOKS procedures for start-session, end-session, stuck-environment force-destroy, re-signing an already-signed digest, operator CIDR change, rotate secrets, and image bump — end-session and stuck-environment force-destroy are LOCALSTACK-VERIFIED (2026-09-03: exhausted `rbstuck` lease at cleanup_attempt 3 refused the automatic retry with exit 3, the audited `--force-retry --generation` run destroyed 59 resources and left `closing` with cleanup_attempt 4 and one forced audit entry); start-session is LOCALSTACK-VERIFIED in CI (run 33757937265); the remaining sections stay CODE-ONLY with the promotion command on each `Executed:` line
- [x] P4-x: session-apply waits for every enabled ECS service and requires one completed deployment whose task definition matches the applied Terraform output; operator positive checks and the runner-only negative check are documented in RUNBOOKS.md
- [x] P4-y: set Fargate `awsvpc` `hostPort` equal to `containerPort`; done because ECS requires equality and the prior plan-drift allowance masked that contract

## Phase 5 — Drift, sweeper, threat model, polish

(expanded when the phase starts)
- [ ] P5-x: per-workflow OIDC subject binding (verify the customized claim on a real token first)
- [ ] P5-5: `bootstrap/preflight.sh` runs `terraform init` (or detects an uninitialized backend) before `terraform state list`, so a fresh checkout that already has `backend.tf` is not treated as empty state (Tier-3 P2 on PR #1)
- [ ] P5-6: `bootstrap/preflight.sh` propagates `TF_VAR_oidc_provider_external=true` into the apply path when the OIDC provider already exists, instead of only printing the instruction (Tier-3 P2 on PR #1)
- [ ] P5-7: `oidc-smoke.yml` drops the plan-reader role secret from the `pull_request` job, since a same-repo PR can edit the workflow and print the ARN (Tier-3 P2 on PR #1)
- [ ] P5-8: exclude the bootstrap state key from the plan-reader read grant, or keep the budget email out of state, because sensitive variables are stored in plaintext state (Tier-3 P2 on PR #1)
- [ ] P5-9: preview secret value is stored in state readable by plan-reader; move to secret_string_wo/ephemeral or split state (Tier-2 P2 on PR #2)
- [ ] P5-10: data bucket name is globally preclaimable; use bucket_prefix or a persisted random suffix and update the deployer S3 ARN pattern (Tier-2 P2 on PR #2)
- [ ] P5-11: bootstrap hardening follow-up from CKV_AWS_18/CKV2_AWS_64 — add a dedicated access-log bucket for Terraform state and keep the now-explicit signing-key policy synchronized with publisher-role changes

## End-of-project decisions (user, low priority)
- [ ] Rewrite or keep the institutional author email on the first 20 commits of main
- [ ] Delete the superseded remote branch feat/phase2-modules
- [ ] Delete the superseded remote branch feat/phase3-ci (PR #3 closed as stale; PR #4 is the real one)
