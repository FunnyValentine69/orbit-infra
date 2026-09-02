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
with `aud` pinned: `plan-reader` (AWS read-only, no writes of any kind,
including Terraform lock objects — `-lock=false` plans — trusted from
`pull_request` and `ref:refs/heads/main`), `deployer` (apply/destroy of
preview environments, state, lease objects), and `publisher` (ECR push
plus signature/attestation writes and KMS sign) — the latter two trusted
only from `ref:refs/heads/main`, with no subject customization or GitHub
environment, so credentials exist only in a workflow already on `main`,
checked out at the triggering SHA with no `ref` input.

**Local-bootstrap deviation:** the Free Plan blocks IAM Identity Center,
so bootstrap runs from an IAM user (MFA, keys local-only, deactivated
between sessions) instead of SSO, confined to the operator's one-time
bootstrap step; CI never uses static keys.

## Consequences

- No static AWS credentials exist anywhere in GitHub Actions.
- A pull-request run, including from a fork, can never obtain `deployer`
  or `publisher`; `oidc-smoke` proves this on every dispatch and PR.
- The local IAM-user deviation depends on deactivating keys between
  sessions; documented rather than hidden.

## Alternatives considered

- **One broad role for all jobs:** rejected — a compromised read-only job
  could otherwise apply or destroy infrastructure.
- **Required-reviewer GitHub environments:** rejected — blocks the
  unattended nightly sweeper for no offsetting benefit.
- **Reusable-workflow subject customization:** rejected — adds indirection
  for no benefit over `ref:refs/heads/main`
