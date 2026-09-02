# ADR 0003: Workload-agnostic contract

Status: Accepted (2026-09-02)

## Context

This platform is a portfolio artifact and must be applyable end to end by
a reviewer with no access to the private upstream workload, while the
"real" demonstration deploys the upstream workload
(`SuperGokou/happyCoding`) for a richer showcase.

## Decision

The `envs/preview` composition takes `api_image`, `api_command` (optional
override), `worker_image` (nullable — `null` disables the worker service),
`worker_command`, and env maps as Terraform variables. The default
`api_image` is a private-ECR digest of this repo's own placeholder (a
minimal FastAPI app with `/health` and an S3 round-trip endpoint),
published by CI before the first apply, so `terraform apply` works with no
private code. For the upstream workload, `worker_image` stays `null`
because its shipped entrypoint module is absent upstream; shipping a guess
would misrepresent functionality. The upstream's S3 integration is out of
scope here because its client passes static credentials rather than
assuming a role, which this platform's IAM-role-only model doesn't support
without upstream changes.

## Consequences

- The stack is reviewable and applyable without the private clone.
- The upstream worker is not demonstrated until upstream ships the missing
  module or a verified alternative command; filed as an upstream issue.
- The upstream S3 integration is not exercised through this platform until
  it stops requiring static keys; the placeholder's S3 endpoint
  demonstrates the IAM-role path instead.

## Alternatives considered

- **Hardcode the upstream image and command:** rejected — breaks
  applyability without private access and couples Terraform to one
  workload.
- **Reimplement the missing worker entrypoint locally:** rejected — this
  repo doesn't own upstream's application code; patching around a missing
  module here would hide the upstream gap instead of surfacing it.
- **Grant the upstream S3 client static keys via Secrets Manager:**
  rejected — reintroduces long-lived credentials this project avoids.
