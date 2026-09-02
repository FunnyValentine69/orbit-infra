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

## Lease lifecycle

Every environment has a durable lease at `leases/<ENV_ID>.json` in the
state bucket (ADR 0006): `open -> closing -> closed | cleanup_failed`,
CAS'd on the S3 object's ETag so concurrent writers never both win.
`scripts/lease.sh` reads/writes it directly; `make close` /
`scripts/close-env.sh` drive it through stage 1 of close (manifest,
scale-to-zero, destroy with retries, `DeleteTaskDefinitions`, cost-
bearing-zero check). See `RUNBOOKS.md`, "Stuck-environment
force-destroy", for recovery from `cleanup_failed` or a stalled
`closing`.

```
make lease-list
make lease-get ENV_ID=<id>
make close TARGET=aws        ENV_ID=<id>
make close TARGET=localstack ENV_ID=<id>
```
