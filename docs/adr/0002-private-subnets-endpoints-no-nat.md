# ADR 0002: Private subnets, interface/gateway endpoints, no NAT

Status: Accepted (2026-09-02)

## Context

ECS tasks need to reach ECR (to pull images), CloudWatch Logs, Secrets
Manager, and SSM (for ECS Exec), plus S3. The conventional way to give
private-subnet tasks that reach is a NAT gateway, which bills per hour and
per GB regardless of whether the workload uses outbound internet access.

## Decision

Tasks run in a single private subnet with no route to a NAT gateway or
internet gateway. VPC interface endpoints cover ECR `api`/`dkr`, CloudWatch
Logs, Secrets Manager, and `ssmmessages`; a free S3 gateway endpoint covers
object storage. Every AWS API a task calls must have a corresponding
endpoint, or the call fails closed. Third-party egress (a data provider API,
package installs at runtime, etc.) is permanently out of scope for this
stack — a NAT gateway or egress proxy would be a separate, explicitly
costed ADR, not an extension of this one.

## Consequences

- No path exists for a compromised or misconfigured task to reach the
  public internet; the private subnet is unreachable from outside the VPC
  except through the ALB in the public subnets.
- Endpoint cost (roughly $0.05/hour for five endpoints, session-hours only)
  replaces NAT cost, and is lower for this traffic pattern.
- Any future requirement for third-party egress needs its own costed
  decision; it cannot ride in silently as an endpoint addition.

## Alternatives considered

- **NAT gateway:** rejected — bills continuously even at zero idle-session
  time in some designs, and grants tasks a default path to the open
  internet that this project's threat model explicitly wants to avoid.
- **Public subnet for tasks:** rejected — puts task ENIs on a route to an
  internet gateway, widening the blast radius for no networking benefit
  here.
- **VPC peering / Transit Gateway for private connectivity:** rejected —
  solves a multi-VPC problem this single-VPC-per-session design doesn't
  have; adds cost and complexity without a corresponding need.
