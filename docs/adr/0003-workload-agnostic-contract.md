# ADR 0003: Workload-agnostic contract

Status: Accepted (2026-09-02). Evidence: LOCALSTACK-VERIFIED for apply/close on LocalStack; every real-AWS behavior in this document is CODE-ONLY until the promotion gate P0-3d runs.

## Context

This platform is a portfolio artifact and must be applyable end to end by
a reviewer with no access to the private upstream workload, while the
"real" demonstration deploys the upstream workload
(`SuperGokou/happyCoding`) for a richer showcase.

## Decision

The `envs/preview` composition takes `api_image`, `redis_image`,
`clickhouse_image`, `api_command` (optional override), `worker_image`
(nullable — `null` disables the worker service), `worker_command`, and env
maps as Terraform variables. On LocalStack, the defaults apply as-is:
`api_image` defaults to `placeholder:local`, the locally built placeholder
image, and the redis/clickhouse modules' `image` variables default to
their public Docker Hub images (`redis:7-alpine`,
`clickhouse/clickhouse-server:24.3-alpine`) — so `terraform apply` works
end to end with no private code and no CI dependency. The real-AWS path
instead requires an explicit `session-apply` mode and private-ECR digests.
`upstream` deploys `orbit-api` and `orbit-clickhouse` from `upstream.lock`
plus Redis from `mirror-images.lock`. `public` deploys the placeholder, Redis,
and ClickHouse from `mirror-images.lock`. Each mode fails closed before lease
open unless its complete three-image set is digest-pinned and its repository
names match `bootstrap/ecr.tf`. The selected mode is recorded in the lease
manifest. For the upstream workload,
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
