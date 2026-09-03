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
`worker_command`, and env maps as Terraform variables; `modules/redis` and
`modules/clickhouse` each take their own `image` variable, not exposed as
an `envs/preview` variable. On LocalStack, the defaults apply as-is:
`api_image` defaults to `placeholder:local`, the locally built placeholder
image, and the redis/clickhouse modules' `image` variables default to
their public Docker Hub images (`redis:7-alpine`,
`clickhouse/clickhouse-server:24.3-alpine`) — so `terraform apply` works
end to end with no private code and no CI dependency. The real-AWS path
instead requires the private-ECR digests that Phase 3's `mirror-images.yml`
and `sign-images.yml` workflows produce, passed in via `api_image` (and,
once wired through, the redis/clickhouse module `image` variables); that
path does not work until those workflows exist. For the upstream workload,
`worker_image` stays `null`
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
