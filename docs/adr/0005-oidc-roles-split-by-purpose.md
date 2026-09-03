# ADR 0005: OIDC roles split by purpose

Status: Accepted (2026-09-02). Evidence: LOCALSTACK-VERIFIED for apply/close on LocalStack; every real-AWS behavior in this document is CODE-ONLY until the promotion gate P0-3d runs.

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

PR CI secrets are limited to the repository owner's own pull requests; a
compromised owner account is outside the threat model. `terraform-plan.yml`
requires both same-repository head ownership and repository-owner PR authorship
before starting a job that reads `LOCALSTACK_AUTH_TOKEN` or
`INFRACOST_API_KEY`. Its top-level token permission is `contents: read`;
`pull-requests: write` is granted only to jobs that post comments.

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
- Accepted for now; harden in Phase 5 (accepted 2026-09-02): all three
  roles trust the same main-ref subject, so any main-branch workflow with
  `id-token: write` can assume any of them; on this solo repo the boundary
  is branch protection on main, not the subject. Hardening candidate for
  Phase 5: per-workflow subject binding via GitHub's OIDC subject
  customization (`workflow` claim), to be verified against a real token
  before adoption.
- The `deployer` role's environment-mutation rights are an enumerated,
  least-privilege policy (`bootstrap/roles.tf`), not the broad
  `EnvironmentMutationPlaceholder` statement used through Phase 2's
  module-building work: separate statements cover EC2 networking, ALB,
  ECS, Cloud Map, CloudWatch log groups, Secrets Manager, the preview
  data bucket, and the ECS execution/task IAM roles, each scoped to a
  resource ARN pattern where AWS supports resource-level permissions and
  to `resources = ["*"]` only where it documents none (EC2 VPC/subnet/
  route-table/IGW/endpoint/SG lifecycle, ELBv2 create/register/tag
  calls, ECS `RegisterTaskDefinition`/`CreateService` plus close-time
  `ListServices`, Cloud Map namespace/service, and the
  close-time full-inventory read `tag:GetResources`). Close-time
  `ecs:ListTasks` and `ecs:DescribeTasks` are the exception among the
  ECS reads: they carry an `ecs:cluster` ARN condition restricting them to
  project clusters (statement `EcsListDescribeTasksForProjectClusters`). An explicit `Deny`
  statement caps the name-substring-scoped IAM grants so the deployer can
  never mutate or pass its own role, `plan-reader`, or `publisher`
  (TODO.md P2-7).

## Amendment 2026-09-02 (PR #2 Tier 2)

The `deployer` role's `iam:CreateRole`/`iam:PutRolePolicy`/
`iam:AttachRolePolicy` grants for execution/task roles are now
conditioned on `iam:PermissionsBoundary` matching a dedicated
`aws_iam_policy.task_boundary` (named `${var.name}-task-boundary`,
`prevent_destroy = true`), which is itself the documented maximum
permission set an execution or task role may hold (ECR pull, project
log-group writes, project secret reads, ECS-Exec ssmmessages, project
data-bucket object actions). Explicit denies block
`iam:DeleteRolePermissionsBoundary` outright and block
`CreateRole`/`PutRolePolicy`/`AttachRolePolicy` whenever the boundary is
absent (`Null`) or does not match this exact ARN
(`StringNotEquals`) — Deny wins regardless of which Allow statement
would otherwise permit the call. `envs/preview/main.tf` computes the
same ARN by name (`arn:<partition>:iam::<account>:policy/${var.name}-task-boundary`)
and wires it into every `ecs-service`/`redis`/`clickhouse` module call
as `permissions_boundary_arn`; see `bootstrap/README.md` and
`envs/preview/README.md` for the naming contract.

Deployer mutation grants across EC2, ELBv2, ECS, Cloud Map, Secrets
Manager, SNS, and CloudWatch are additionally scoped, where the AWS IAM
condition-key reference documents support for it, to
`aws:RequestTag/Project` (create actions) or the service's
`ResourceTag` key (delete/modify/read actions), compared against
`var.project_tag` (default `orbit-infra`, matching
`envs/preview/main.tf`'s `default_tags.Project`). Most actions the
reference documents no condition key for are left unconditioned, each
flagged with a comment citing the verified condition-key table; five
exceptions (`ec2:ReplaceRoute`, `ec2:ReplaceRouteTableAssociation`,
`ec2:ModifySecurityGroupRules`, `elasticloadbalancing:RegisterTargets`,
`elasticloadbalancing:DeregisterTargets`) are conditioned on the same
`ResourceTag/Project` pattern as their sibling actions on the same
resource type even though the reference documents no condition key for
them — a deliberate defense-in-depth choice (PR#2 Tier 2b F1), each
flagged in a roles.tf comment as not table-backed rather than presented
as verified. `resources` stays `["*"]` on these statements — AWS does not
support resource-level ARN scoping for freshly-created resources with
unknown IDs, but IAM still evaluates the tag conditions against a `"*"`
resource, so the scoping is real even though the wildcard-count grep does
not shrink.

Two new service-linked-role allowances (`AWSServiceRoleForElasticLoadBalancing`,
`AWSServiceRoleForECS`) are pinned to their exact ARNs and gated by
`iam:AWSServiceName`, replacing implicit reliance on IAM auto-creating
these roles.

## Amendment 2026-09-02 (PR #2 Tier 2b, F3)

The `deployer` role's single inline policy exceeded the 10,240-character
inline-policy-aggregate quota. It is now six `aws_iam_policy`
customer-managed policies (`${var.name}-deployer-state`, `-ec2`,
`-elb-ecs`, `-data`, `-iam`, `-guard`), attached via
`aws_iam_role_policy_attachment`, each under the 6,144-character
managed-policy quota — grouped by service, statement content unchanged.
`bootstrap/policy-size-check.sh` renders a LocalStack plan and checks
every planned policy document against both quotas; it runs as the
`policy-size` gate in `scripts/gates.sh`.

Also in this amendment: the F4 `AuthorizeSecurityGroupIngress`/
`AuthorizeSecurityGroupEgress`/`Revoke*` statements are now allowed via
two paths — an `aws:RequestTag/Project`-conditioned path scoped to the
`security-group-rule` resource type (for the separate
`aws_vpc_security_group_ingress_rule`/`egress_rule` resources in
`envs/preview/main.tf`, which set `tags =`) and an
`ec2:ResourceTag/Project`-conditioned path scoped to the pre-existing
`security-group*` resource (for the inline `ingress`/`egress` blocks in
`modules/network/main.tf` and `envs/preview/main.tf`, which issue
Authorize/Revoke calls with no tags on the call itself — the prior
RequestTag-only condition never matched for these, which would have
denied SG rule creation for the composition's actual security groups).

## Alternatives considered

- **One broad role for all jobs:** rejected — a compromised read-only job
  could otherwise apply or destroy infrastructure.
- **Required-reviewer GitHub environments:** rejected — blocks the
  unattended nightly sweeper for no offsetting benefit.
- **Reusable-workflow subject customization:** rejected — adds indirection
  for no benefit over `ref:refs/heads/main`
