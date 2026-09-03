# modules/clickhouse

Thin wrapper over `modules/ecs-service`: a single-node ClickHouse
Fargate service with `CLICKHOUSE_DB`/`CLICKHOUSE_USER` plaintext env
vars and `CLICKHOUSE_PASSWORD` sourced from a caller-supplied Secrets
Manager ARN, plus an HTTP `/ping` health check with a 30s start period
(the alpine image ships `wget`).

## Variables

`name` (default `"clickhouse"`), `env_id` (1-12 lowercase alphanumerics
and hyphens, no leading or trailing hyphen), `enabled`, `cluster_arn`,
`image` (default `clickhouse/clickhouse-server:24.3-alpine`; the preview
composition passes the private-ECR mirror digest for real-AWS sessions),
`subnet_ids`,
`security_group_ids`, `cloud_map_namespace_id` /
`register_service_discovery`, `namespace_name` (used only to compute
`discovery_dns_name`), `database` (default `"app"`), `user` (default
`"default"`), `password_secret_arn` (required), `cpu` (default `512`),
`memory` (default `1024`), `tags`.

## Outputs

`discovery_dns_name` (`${name}.${namespace_name}`, null if
`namespace_name` unset), `port` (`8123`), `service_name`.
