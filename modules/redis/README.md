# modules/redis

Thin wrapper over `modules/ecs-service`: a single-node Redis Fargate
service with no persistence (`--appendonly no`), a 200mb allkeys-lru
memory cap, and a `redis-cli ping` health check.

## Variables

`name` (default `"redis"`), `env_id` (1-12 lowercase alphanumerics and
hyphens, no leading or trailing hyphen), `enabled`, `cluster_arn`, `image`
(default `redis:7-alpine`; P3-2 replaces this with the private-ECR
mirror digest), `subnet_ids`, `security_group_ids`,
`cloud_map_namespace_id` / `register_service_discovery`, `namespace_name`
(used only to compute `discovery_dns_name`), `cpu` (default `256`),
`memory` (default `512`), `tags`.

## Outputs

`discovery_dns_name` (`${name}.${namespace_name}`, null if
`namespace_name` unset), `port` (`6379`), `service_name`.
