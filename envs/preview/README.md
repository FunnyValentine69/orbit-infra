# envs/preview

Ephemeral preview environment: network, ECS cluster, ALB, api/worker
services, clickhouse, redis, S3 data bucket.

## Variables

- `target` — `aws` (default) or `localstack`.
- `env_id` — required; suffixes every resource name/tag.
- `operator_cidr` — required, no default; CIDR allowed to reach the ALB
  on port 80 (ADR 0004). Never commit a real value — the Makefile
  resolves it via `checkip.amazonaws.com`, or set `OPERATOR_CIDR` in the
  environment.

## State keys

`backend.tf` is a partial S3 backend config. `backend.aws.hcl.example`
holds the shared bucket/region/lock settings (copy to `backend.aws.hcl`
locally if you want your own; the Makefile falls back to the example
when it's absent — no secrets in either). The Makefile injects the
per-environment state key: `envs/preview/<ENV_ID>.tfstate`.

## Commands

```
make plan    TARGET=aws        ENV_ID=<id>
make apply   TARGET=aws        ENV_ID=<id>
make destroy TARGET=aws        ENV_ID=<id>

make apply   TARGET=localstack ENV_ID=<id>
```

LocalStack runs use a local backend keyed by `ENV_ID`
(`terraform.localstack.<ENV_ID>.tfstate`), rendered from
`localstack.backend_override.tf.example` — separate state per
environment, never touching the AWS backend.
