# Partial backend config: bucket/region/use_lockfile/encrypt come from
# backend.aws.hcl (see backend.aws.hcl.example); the per-environment state
# key is injected by the Makefile as
# -backend-config="key=envs/preview/<ENV_ID>.tfstate" so each ephemeral
# environment gets its own state file in the shared bucket.
terraform {
  backend "s3" {}
}
