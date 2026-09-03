# envs/preview

Ephemeral preview environment: network, ECS cluster, ALB, api/worker
services, clickhouse, redis, S3 data bucket.

## Variables

- `target` — `aws` (default) or `localstack`.
- `env_id` — required; suffixes every resource name/tag. Must be 1-12 lowercase alphanumerics and hyphens, with no leading or trailing hyphen.
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
(`terraform.localstack.<ENV_ID>.tfstate`). `backend_override.tf` is
rendered from `localstack.backend_override.tf.example` and removed again
within the same command (subshell + `trap ... EXIT`), and
`TF_DATA_DIR=.terraform-localstack-<ENV_ID>` gives each environment its
own provider cache — separate state and data dir per environment, never
touching the AWS backend. The `aws` target refuses to run while
`backend_override.tf` is present.
