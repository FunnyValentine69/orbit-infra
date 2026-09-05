# Conftest plan fixture provenance

`good-plan.json` and `bad-plan.json` are recorded from Terraform plans against
LocalStack. Never hand-edit either sidecar; change its Terraform root and
re-record both plans with `make record-conftest-fixtures` instead.

- LocalStack version: `2026.8.1` (running instance, `curl -s localhost:4566/_localstack/health` -> `.version`; LocalStack CLI reports `2026.8.0`)
- Terraform version: `1.16.0` (`terraform version`; also embedded as `.terraform_version` in both plan JSON files, format_version `1.2`)
- Recording date: `2026-09-04` (re-recorded)
- Branch: `feat/p5-3-conftest-gate`
- Source commit: `46e1cdd`
- Note: re-recorded because `good-root`/`bad-root` were updated to reference
  their S3 buckets via `.bucket` (instead of the prior form) with explicit
  bucket names; envs/preview/main.tf and bootstrap/state.tf were updated the
  same way. Fixture JSON reflects that root change.
- Exact commands:
  - `make record-conftest-fixtures`, which for each of `good-root` and `bad-root` runs:
    - `env -u AWS_PROFILE AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 terraform -chdir="<root>" init -input=false -upgrade=false`
    - `env -u AWS_PROFILE AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 terraform -chdir="<root>" plan -input=false -out=plan.tfplan`
    - `env -u AWS_PROFILE AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 terraform -chdir="<root>" show -json plan.tfplan > tests/fixtures/conftest/<name>-plan.json`
    - `plan.tfplan` removed after each run; `.terraform/` is gitignored and left in place
- Rule: fixtures are re-recorded rather than edited. Never hand-edit `good-plan.json` or `bad-plan.json`; if the fixture is wrong, fix the Terraform root under `tests/fixtures/conftest/{good,bad}-root` and re-run `make record-conftest-fixtures`.
