# ADR 0006: Preview environment lease lifecycle

Status: Accepted (2026-09-02)

## Context

Environments are created/destroyed by independent CI dispatches that can be interrupted, retried, or overlap the nightly sweeper. Without a durable, race-safe state record, a crashed apply or overlapping destroy could orphan billable resources.

## Decision

Each `env_id` has a durable lease at `leases/<env_id>.json` with states `open → closing → closed | cleanup_failed` and a monotonically increasing `generation`. Every transition is a compare-and-swap (S3 conditional write on the ETag, asserting prior state/generation) — two writers can never both win. Apply order: runner-CIDR check → lint → checkov → create lease (only if none exists or `closed`, generation N+1) → init → plan → apply; static gate failures never create a lease or resources. Any failure after the lease exists triggers stage 1 of close in the same job.

Close is two-stage since task definitions delete asynchronously (up to 24h) while a hosted job caps at 6. Stage 1 sets `closing`, persists a manifest (state resources, task ARNs, tag inventory), scales to zero, destroys with retries, calls `DeleteTaskDefinitions`, verifies cost-bearing resources are gone, ends `closing` with state intact. Stage 2 (sweeper) re-checks the manifest; once every task definition is deleted, it removes state versions and sets `closed`. Any failure sets `cleanup_failed`, keeping state for retry — the sweeper shares `preview-<env_id>` concurrency with apply/destroy (`queue: max`) so they never overlap. `closed` leases prune after 7 days.

## Consequences

- An interrupted apply/destroy always leaves a lease the sweeper finishes, never a silently orphaned environment.
- The two-stage close adds latency, correct given async AWS deletion.
- Every taggable resource carries the env tag — the source of truth for "is this environment really gone."

## Alternatives considered

- **Terraform state alone as the record:** rejected — reflects only the last successful apply, not an in-progress transition.
- **DynamoDB lock table for leases:** rejected — a second persistent resource for what S3 ETag compare-and-swap already provides.
- **Single-stage close, longer timeout:** rejected — hosted jobs cap at 6 hours; task-definition deletion can take up to 24.
