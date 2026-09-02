# ADR 0001: Ephemeral over always-on

Status: Accepted (2026-09-02)

## Context

This platform exists to demonstrate infrastructure engineering, not to run
a production service continuously. An always-on ECS/ALB/ClickHouse/Redis
stack would carry Fargate, ALB, and data-transfer costs 24/7 for a workload
that is only ever exercised on demand.

## Decision

Every cost-bearing resource (VPC, ALB, ECS services and tasks, Cloud Map
namespace, S3 data bucket) is created by an explicit `session-apply`
dispatch tied to an `env_id`, and torn down by an explicit
`session-destroy` dispatch or the nightly sweeper. Nothing runs between
sessions. Only near-zero-cost persistent resources (state bucket, IAM/OIDC,
KMS key, ECR repos, Budgets alarm) survive outside a session.

## Consequences

- Near-zero idle cost; a full billing cycle with no open session costs
  roughly the standing KMS fee.
- Every environment needs a durable lease and a two-stage close protocol
  (ADR 0006) to be safe against interrupted or overlapping dispatches.
- Cold-start latency (VPC + ALB + ECS bring-up) is paid on every session
  rather than amortized once.

## Alternatives considered

- **Always-on single environment:** rejected — pays full-time Fargate/ALB
  cost for a workload with no continuous traffic; defeats the near-zero-idle
  goal.
- **Serverless-only (no ECS)** — rejected: the point of this project is to
  demonstrate real ECS/Fargate networking and lease management, which a
  fully serverless design would not exercise.
- **Scheduled on/off window (e.g. business hours)** — rejected: still pays
  for idle hours within the window and adds a scheduler dependency without
  removing the need for a lease/lifecycle mechanism.
