# ADR 0005: OIDC roles split by purpose

Status: Accepted (2026-09-02)

## Context

CI needs AWS credentials for three distinct jobs — read-only plan review,
applying/destroying preview environments, and pushing/signing images —
with very different blast radii. Static AWS keys in GitHub secrets are a
standing leak risk this project avoids entirely.

## Decision

Three IAM roles federate through one GitHub OIDC provider, each trusting
only the immutable-ID subject `repo:<owner>@<owner_id>/<repo>@<repo_id>:...`
with `aud` pinned. All three — `plan-reader` (AWS read-only, no writes of
any kind, including Terraform lock objects — `-lock=false` plans),
`deployer` (apply/destroy of preview environments, state, lease objects),
and `publisher` (ECR push plus signature/attestation writes and KMS
sign) — trust only `ref:refs/heads/main`, with no subject customization or
GitHub environment, so credentials exist only in a workflow already on
`main`, checked out at the triggering SHA with no `ref` input. No role
trusts the `pull_request` subject: pull-request-triggered jobs receive no
AWS credentials at all. Pull-request Terraform plans instead run against
LocalStack (see ADR 0008); a real plan-reader read against AWS state
happens only from `main`.

**Local-bootstrap deviation:** the Free Plan blocks IAM Identity Center,
so bootstrap runs from an IAM user (MFA, keys local-only, deactivated
between sessions) instead of SSO, confined to the operator's one-time
bootstrap step; CI never uses static keys.

## Consequences

- No static AWS credentials exist anywhere in GitHub Actions.
- No role's trust policy trusts the `pull_request` subject, so a
  pull-request-triggered job cannot obtain a credential for any of the
  three roles regardless of same-repo or fork origin. `oidc-smoke`'s
  same-repository pull_request runs are designed to prove this: each of
  the three jobs is designed to prove its role assumption fails with
  AccessDenied on every same-repo pull_request run and on every
  workflow_dispatch not from `refs/heads/main`; the real-AWS run is
  recorded in STATE.md when executed. Fork PRs skip the jobs entirely
  (green-by-skip, via the `head.repo.full_name == github.repository`
  guard); that guard is a cost/no-op filter, not a security boundary,
  since no role trusts the `pull_request` subject in the first place.
- Pull-request-triggered Terraform plans have no AWS credentials to use;
  they run against LocalStack in CI (see ADR 0008).
- The local IAM-user deviation depends on deactivating keys between
  sessions; documented rather than hidden.

## Alternatives considered

- **One broad role for all jobs:** rejected — a compromised read-only job
  could otherwise apply or destroy infrastructure.
- **Required-reviewer GitHub environments:** rejected — blocks the
  unattended nightly sweeper for no offsetting benefit.
- **Reusable-workflow subject customization:** rejected — adds indirection
  for no benefit over `ref:refs/heads/main`
