# ADR 0008: LocalStack development lane

Status: Accepted (2026-09-02)

## Context

The AWS Free Plan denies, via AWS-managed service control policies, several
services this stack needs (S3 bucket creation, ECR, ECS, VPC, ALB, KMS,
OIDC providers), and the account owner has chosen not to upgrade to the
Paid Plan yet. Separately, the GitHub Student Developer Pack grants a
LocalStack plan whose service coverage equals the Ultimate tier, with
sanctioned use in CI.

## Decision

Phases 2-4 develop and acceptance-test against LocalStack, both locally
and in CI. Every root module takes a `target` variable (`"aws"` or
`"localstack"`) that selects provider endpoints; the composition never
contains LocalStack-only resources. The AWS Budgets resource is toggled
off when `target = "localstack"`, since Budgets is not emulated. Real AWS
remains the final promotion step once the platform is proven on
LocalStack. Every LocalStack job runs `make bootstrap-apply TARGET=localstack`
after the emulator health check and before any plan or apply so the versioned
state bucket exists.

## Consequences

- Most of the stack — ECS Fargate, ECR, VPC/SG, IAM, STS, KMS asymmetric
  keys, S3, Cloud Map, CloudWatch Logs, Secrets Manager, SSM — is proven
  functionally on LocalStack before it ever touches AWS.
- Three things are verified only on real AWS: AWS Budgets, ECS Exec (`docker
  exec` substitutes locally), and exact OIDC trust-policy condition
  semantics — LocalStack's `AssumeRoleWithWebIdentity` ignores conditions,
  so the PR-refusal test in `oidc-smoke.yml` is real-AWS-only.
- The composition must stay portable across both targets; any
  LocalStack-only resource would break the AWS promotion path.

## Alternatives considered

- **Upgrade to the AWS Paid Plan now:** rejected — the owner wants no AWS
  spend until the platform is otherwise proven.
- **LocalStack Community edition:** rejected — lacks ECS, ECR, and ALB
  support, which this stack depends on.
- **Another cloud's free credits:** rejected — rewrites the AWS-specific
  design (OIDC provider, IAM roles, ECS Fargate) this project is built
  around.
