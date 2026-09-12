# ADR 0008: LocalStack development lane

Status: Accepted (2026-09-02); amended 2026-09-08 — the portfolio scope is recorded below

## Context

The portfolio needs repeatable infrastructure and lifecycle evidence without
deploying the service stack into AWS. The GitHub Student Developer Pack grants
a LocalStack license with the service coverage needed by the composition and
sanctioned use in CI.

## Decision

Phases 2-4 develop and acceptance-test against LocalStack, both locally
and in CI. Every root module takes a `target` variable (`"aws"` or
`"localstack"`) that selects provider endpoints; the composition never
contains LocalStack-only resources. The AWS Budgets resource is toggled
off when `target = "localstack"`, since Budgets is not emulated. The real-AWS deployment tail is out of scope for this portfolio; deployed-service behaviour is verified on LocalStack and IAM policy evaluation with the AWS policy simulator against the real account. Every LocalStack job runs `make bootstrap-apply TARGET=localstack`
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

- **Deploy the service stack to real AWS for this portfolio:** rejected — the
  LocalStack and policy-simulator lanes cover the intended public evidence.
- **LocalStack Community edition:** rejected — lacks ECS, ECR, and ALB
  support, which this stack depends on.
- **Another cloud's free credits:** rejected — rewrites the AWS-specific
  design (OIDC provider, IAM roles, ECS Fargate) this project is built
  around.

## Amendment 2026-09-08: portfolio boundary

Real AWS is not a pending portfolio milestone. The composition remains
portable, while the public evidence stops at LocalStack execution and real-account
IAM policy simulation. The optional deployment sequence remains in `TODO.md`
under P0-3b for future use.
