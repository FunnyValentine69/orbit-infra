# modules/ecs-service

Generic single-container Fargate service: log group, execution role
(managed `AmazonECSTaskExecutionRolePolicy` plus an inline
`secretsmanager:GetSecretValue` statement when `secrets` is non-empty),
task role (SSM channel policy when `enable_execute_command`, plus an
optional caller-supplied inline policy), an ARM64 Fargate task
definition, an optional Cloud Map service, and the ECS service itself.

## Caller responsibilities

This module has no provider block; the caller passes providers. The
caller must supply `default_tags` and this module additionally stamps
`env_id` on every taggable resource.

`enabled = false` produces zero resources (every resource is `count`-gated
on it), for the optional `worker` service.

The execution and task IAM roles are named from `"${env_id}-${name}-"`
truncated to 32 characters and passed as `name_prefix` (not the full
`var.name`), so AWS's random suffix always fits regardless of caller
name length; the ECS service, log group, and Cloud Map name stay on
the full `var.name`.

## Variables

`name`, `env_id`, `cluster_arn`, `image`, `command` (default `null`),
`container_port`, `cpu` (default `256`), `memory` (default `512`), `env`,
`secrets` (name => Secrets Manager ARN, default `{}`), `subnet_ids`,
`security_group_ids`, `assign_public_ip` (default `false`), `enabled`
(default `true`), `enable_execute_command` (default `true`),
`cloud_map_namespace_id` / `register_service_discovery` (default `false`
— split in two because a namespace created in the same apply has an id
unknown until apply, and count/for_each need a plan-time-known value),
`alb_target_group_arn` (optional), `log_retention_days` (default `7`),
`health_check` (optional), `task_role_policy_json` (optional), `tags`.
