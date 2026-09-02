# envs/preview

Ephemeral preview environment: network, ECS cluster, ALB, api/worker
services, clickhouse, redis, S3 data bucket.

## Variables

- `target` — `aws` (default) or `localstack`.
- `region` — AWS provider region (default `us-east-1`); Make targets pass
  the exported `AWS_REGION` value explicitly.
- `env_id` — required; suffixes every resource name/tag. Must be 1-12 lowercase alphanumerics and hyphens, with no leading or trailing hyphen.
- `operator_cidr` — required, no default; CIDR allowed to reach the ALB
  on port 80 (ADR 0004). Never commit a real value — the Makefile
  resolves it via `checkip.amazonaws.com`, or set `OPERATOR_CIDR` in the
  environment.
- `project_tag` — authoritative `Project` tag (default `orbit-infra`),
  matching the bootstrap deployer-policy condition even when callers
  replace `tags` with their own map.

## State keys

`backend.tf` is a partial S3 backend config. `backend.aws.hcl.example`
holds the shared bucket/region/lock settings (copy to `backend.aws.hcl`
locally if you want your own; the Makefile falls back to the example
when it's absent — no secrets in either). The Makefile injects the
per-environment state key: `envs/preview/<ENV_ID>.tfstate`.

## Task permissions boundary

Every ECS execution/task role created here (api, worker, redis,
clickhouse) gets `permissions_boundary_arn = local.task_boundary_arn`,
computed as `arn:<partition>:iam::<account>:policy/${var.name}-task-boundary`.
This must exactly match the `${var.name}-task-boundary` policy
`bootstrap/roles.tf` creates (naming contract — no cross-root data
source, just matching name strings); on real AWS the deployer's
`iam:CreateRole`/`iam:PutRolePolicy`/`iam:AttachRolePolicy` grants are
denied unless this ARN is set as the boundary.

## Commands

```
make placeholder-build

make plan    TARGET=aws        ENV_ID=<id>
make apply   TARGET=aws        ENV_ID=<id>
make destroy TARGET=aws        ENV_ID=<id>

make apply   TARGET=localstack ENV_ID=<id>
```

`api_image` defaults to `placeholder:local`, which nothing builds
automatically; run `make placeholder-build` first, or `make apply
TARGET=localstack ...` fails fast with a reminder.

LocalStack runs use a local backend keyed by `ENV_ID`
(`terraform.localstack.<ENV_ID>.tfstate`). Because Terraform loads every
`*_override.tf` file in a directory, concurrent runs cannot share
`envs/preview/`: each `ENV_ID` gets its own rsync'd copy of this
composition under `.preview-runs/<ENV_ID>/`, with
`backend_override.tf` rendered inside that copy from
`localstack.backend_override.tf.example`, and every terraform command
run with `-chdir` into it and its own `TF_DATA_DIR=.terraform-localstack`
— separate state and data dir per environment, never touching the AWS
backend. Each sync deletes stale source files while excluding the data
directory, rendered override, and `*.tfstate*` files. `PREVIEW_ROOT`
(exported by the Makefile, defaulting to
`envs/preview` on the `aws` target) points at the active run directory.
The `aws` target refuses to run while `envs/preview/backend_override.tf`
is present.

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
