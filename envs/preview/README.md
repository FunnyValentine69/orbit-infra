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
- `alert_email` — optional, sensitive; when set (must be a single valid address) it subscribes to the alerts SNS topic. Never commit a literal value.
- `project_tag` — authoritative `Project` tag (default `orbit-infra`),
  matching the bootstrap deployer-policy condition even when callers
  replace `tags` with their own map.
- `api_image`, `redis_image`, `clickhouse_image` — task images. LocalStack
  uses local/public defaults; real-AWS session dispatches pass digest-pinned
  private-ECR references from `upstream.lock` and `mirror-images.lock`.

## State keys

`backend.tf` is a partial S3 backend config. `backend.aws.hcl` is required
for the AWS target; there is no example-file fallback. Generate it with
`scripts/write-preview-backend.sh`, which derives the bucket and region from
bootstrap's committed `var.name`/`var.region` defaults and the
`${var.name}-tfstate` naming contract. The Makefile injects the per-environment
state key: `envs/preview/<ENV_ID>.tfstate`.

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

For AWS, `make plan` writes `envs/preview/tfplan.bin` and `make apply`
non-interactively consumes that exact saved plan. The session workflow removes
the plan file on success or failure.

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
backend. Each sync copies the committed `.terraform.lock.hcl`, deletes stale
source files, and excludes only Terraform data directories, the rendered
override, and `*.tfstate*` files. `PREVIEW_ROOT`
(exported by the Makefile, defaulting to
`envs/preview` on the `aws` target) points at the active run directory.
The `aws` target refuses to run while `envs/preview/backend_override.tf`
is present.

Make does not default destructive commands to AWS: callers must provide
`TARGET=aws` or `TARGET=localstack`. The LocalStack branch unsets
`AWS_PROFILE`, supplies test credentials, sets
`AWS_EC2_METADATA_DISABLED=true`, and uses an explicit localhost endpoint.
Cleanup and lease scripts pass that endpoint to every AWS CLI invocation;
the AWS branch rejects a LocalStack endpoint. Their shared wrapper also sets
five-second connect and 20-second read limits plus a 30-second outer timeout.

Image overrides: set `TF_VAR_api_image`, `TF_VAR_redis_image`, or `TF_VAR_clickhouse_image` in the environment before `make plan/apply`; an `api_image` override also skips the `placeholder:local` build check. On `target=aws` every image must be a digest-pinned private-ECR reference (validated at plan time).

## Lease lifecycle

Every environment has a durable lease at `leases/<ENV_ID>.json` in the
state bucket (ADR 0006): `open -> closing -> closed | cleanup_failed`,
CAS'd on the S3 object's ETag so concurrent writers never both win.
`scripts/lease.sh` reads/writes it directly; `make close` /
`scripts/close-env.sh` drive it through stage 1 of close (retry-merged
manifest, discovery and scale-to-zero for every service, destroy with retries,
asynchronous `DeleteTaskDefinitions`, and full inventory re-query). The
candidate union includes the prior manifest, Terraform state identifiers, ECS
discovery, and tag inventories. The Tagging API is discovery-only; one exact
verifier records `gone`, `pending`, `live`, or `indeterminate` per candidate,
including partial results on every retry. Stale tag entries are retained in
`manifest.stale_tag_entries`; only deadline-expired `live` or `indeterminate`
results fail stage 1.

`cleanup_attempt`, `next_retry_at`, and `manual_intervention_required` are
CAS-persisted per generation. Three automatic stage-1 executions are allowed;
after the third failure an explicit, audited `--force-retry` is required. A
successful stage 1 leaves the lease `closing` and retains state; only the
sweeper removes state versions and sets `closed`. The LocalStack-only inactive
task-definition deletion allowance is recorded in the manifest. Host-port plan
drift is tracked separately and never changes cleanup predicates. See
`RUNBOOKS.md`, "Stuck-environment force-destroy", for terminal recovery.

```
make lease-list TARGET=aws
make lease-get TARGET=aws ENV_ID=<id>
make close TARGET=aws        ENV_ID=<id>
make close TARGET=localstack ENV_ID=<id>
```
