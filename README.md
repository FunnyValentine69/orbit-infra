# orbit-infra

Ephemeral, near-zero-idle AWS platform for a containerized workload: Terraform, ECS Fargate (ARM64), GitHub Actions with OIDC (no static cloud keys), signed images, per-environment lease lifecycle.

## Status

Phase 0: bootstrap in progress; see STATE.md.

## Upstream

The reference workload is a private repository, `SuperGokou/happyCoding`, used with its owner's permission. Its source and images are never published; this repository deploys any image that satisfies the workload contract (see ARCHITECTURE.md once written), and ships a public placeholder image so the stack can be applied without the private upstream.
