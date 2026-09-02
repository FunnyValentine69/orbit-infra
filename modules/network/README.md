# modules/network

Creates one VPC per environment: two public subnets across two AZs (the
ALB requires at least two AZs) and one private subnet in a single AZ,
where every ECS task runs.

## No-NAT invariant

There is no NAT gateway and no default route in the private route table.
Private-subnet reachability to AWS APIs is entirely through VPC endpoints:
a free S3 gateway endpoint, plus (when `enable_interface_endpoints = true`)
interface endpoints for `ecr.api`, `ecr.dkr`, `logs`, `secretsmanager`, and
`ssmmessages`, all placed in the private subnet with private DNS enabled.
See ADR 0002 for the full rationale.

## Cost

Each interface endpoint costs roughly $0.01/hour; five endpoints run about
$0.05/hour, session-hours only. The S3 gateway endpoint is free.

## Caller responsibilities

This module has no provider block; the caller passes providers. The
caller must supply `default_tags` and this module additionally stamps
`env_id` on every taggable resource.

## Variables

`name`, `env_id` (1-12 lowercase alphanumerics and hyphens, no leading or
trailing hyphen), `cidr` (default `10.42.0.0/16`), `azs` (default: look up
the first two available AZs), `enable_interface_endpoints` (default
`true` — set `false` where LocalStack doesn't emulate a given service),
`tags`.
