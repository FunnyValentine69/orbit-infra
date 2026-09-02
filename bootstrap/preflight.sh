#!/usr/bin/env bash
# preflight.sh — read-only AWS ownership discovery before P0-6 bootstrap Terraform.
# Never creates or modifies AWS resources. See bootstrap/README.md.
set -euo pipefail

PROJECT="orbit-infra"
SUFFIX="79s5rw"
NAME="${PROJECT}-${SUFFIX}"
AWS_PROFILE="${AWS_PROFILE:-orbit}"
AWS_REGION="${AWS_REGION:-us-east-1}"

DRY_RUN=0
BLOCKED=0

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required by preflight.sh (OIDC audience check) but was not found on PATH" >&2
  exit 3
fi

usage() {
  cat <<EOF
Usage: bootstrap/preflight.sh [--dry-run] [--help]

Read-only AWS discovery for the dedicated resource names bootstrap/ (P0-6)
would create, plus the GitHub OIDC provider. Classifies each as absent
(safe to create), present-and-owned-by-us (UNKNOWN-OWNERSHIP, blocks),
or (OIDC only) present-and-external (bootstrap will reference it).

Env overrides: AWS_PROFILE (default orbit), AWS_REGION (default us-east-1)

Exit codes:
  0  no BLOCK lines
  2  one or more BLOCK lines
  3  AWS credentials not available for the given profile

Options:
  --dry-run   print every aws command that would run, without executing any
  --help      show this message
EOF
}

for arg in "$@"; do
  case "$arg" in
    --help) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

AWS_BASE=(aws --profile "$AWS_PROFILE" --region "$AWS_REGION")

# State-aware retries: a resource whose Terraform address is already in
# `terraform state list` is classified MANAGED, not BLOCK, since it is a
# prior apply's output rather than an ownership conflict.
STATE_LIST=""
in_state() {
  # $1 = terraform address
  [[ -n "$STATE_LIST" ]] && grep -qxF "$1" <<<"$STATE_LIST"
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  :
else
  STATE_LIST="$(terraform -chdir=bootstrap state list 2>/dev/null || true)"
fi

run_aws() {
  # $1 = human label for --dry-run, remaining args = the aws subcommand/args
  local label="$1"; shift
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: ${AWS_BASE[*]} $*"
    return 0
  fi
  "${AWS_BASE[@]}" "$@"
}

block() {
  echo "BLOCK: $*"
  BLOCKED=1
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "== preflight.sh --dry-run =="
  echo "NAME=$NAME PROFILE=$AWS_PROFILE REGION=$AWS_REGION"
  echo "-- terraform state --"
  echo "DRY-RUN: terraform -chdir=bootstrap state list"
  echo "-- caller identity --"
  run_aws "identity" sts get-caller-identity --query Arn --output text
  echo "-- S3 state bucket --"
  run_aws "s3" s3api head-bucket --bucket "${NAME}-tfstate"
  echo "-- IAM roles --"
  for role in "${NAME}-plan-reader" "${NAME}-deployer" "${NAME}-publisher"; do
    run_aws "iam" iam get-role --role-name "$role"
  done
  echo "-- ECR repositories --"
  for repo in "${NAME}/placeholder" "${NAME}/orbit-api" "${NAME}/orbit-worker" "${NAME}/orbit-clickhouse" "${NAME}/mirror/clickhouse" "${NAME}/mirror/redis"; do
    run_aws "ecr" ecr describe-repositories --repository-names "$repo"
  done
  echo "-- KMS alias --"
  run_aws "kms" kms describe-key --key-id "alias/${NAME}-signing"
  echo "-- Budget --"
  run_aws "budgets" budgets describe-budget --account-id "<account-id>" --budget-name "${NAME}-monthly"
  echo "-- OIDC provider --"
  run_aws "iam-oidc" iam list-open-id-connect-providers --output json
  echo "== dry-run complete; no AWS calls executed =="
  exit 0
fi

CALLER_ARN=""
CALLER_ERR_FILE="$(mktemp)"
if ! CALLER_ARN=$("${AWS_BASE[@]}" sts get-caller-identity --query Arn --output text 2>"$CALLER_ERR_FILE"); then
  CALLER_ERR="$(sed -E 's/[0-9]{12}/************/g' "$CALLER_ERR_FILE")"
  rm -f "$CALLER_ERR_FILE"
  echo "BLOCK: caller identity failed: $CALLER_ERR" >&2
  echo "AWS credentials not available for profile $AWS_PROFILE; run: aws configure --profile orbit (Free Plan has no Identity Center; see RUNBOOKS.md)" >&2
  exit 3
fi
rm -f "$CALLER_ERR_FILE"
ACCOUNT_ID=""
if ! ACCOUNT_ID=$("${AWS_BASE[@]}" sts get-caller-identity --query Account --output text 2>&1); then
  block "caller identity lookup failed: $ACCOUNT_ID"
  ACCOUNT_ID=""
fi
MASKED_ARN=$(echo "$CALLER_ARN" | sed -E 's/[0-9]{12}/************/')

echo "== preflight: $NAME =="
echo "profile=$AWS_PROFILE region=$AWS_REGION caller=$MASKED_ARN"
echo

check_s3_bucket() {
  local bucket="${NAME}-tfstate"
  local err
  if err=$("${AWS_BASE[@]}" s3api head-bucket --bucket "$bucket" 2>&1); then
    if in_state "aws_s3_bucket.state"; then
      echo "MANAGED: s3_bucket $bucket already in state"
    else
      block "s3_bucket $bucket exists; confirm ownership before bootstrap; if confirmed, import with: terraform -chdir=bootstrap import aws_s3_bucket.state $bucket"
    fi
  else
    if echo "$err" | grep -qE '\(404\)|\(NoSuchBucket\)'; then
      echo "OK: s3_bucket $bucket absent"
    else
      block "s3_bucket $bucket check failed: $err"
    fi
  fi
}

check_iam_role() {
  local role="$1" address="$2"
  local err
  if err=$("${AWS_BASE[@]}" iam get-role --role-name "$role" 2>&1); then
    if in_state "$address"; then
      echo "MANAGED: iam_role $role already in state"
    else
      block "iam_role $role exists; confirm ownership before bootstrap; if confirmed, import with: terraform -chdir=bootstrap import $address $role"
    fi
  else
    if echo "$err" | grep -qi "NoSuchEntity"; then
      echo "OK: iam_role $role absent"
    else
      block "iam_role $role check failed: $err"
    fi
  fi
}

check_ecr_repo() {
  local repo="$1" short="${1#${NAME}/}"
  local err
  if err=$("${AWS_BASE[@]}" ecr describe-repositories --repository-names "$repo" 2>&1); then
    if in_state "aws_ecr_repository.repos[\"$short\"]"; then
      echo "MANAGED: ecr_repository $repo already in state"
    else
      block "ecr_repository $repo exists; confirm ownership before bootstrap; if confirmed, import with: terraform -chdir=bootstrap import 'aws_ecr_repository.repos[\"$short\"]' $repo"
    fi
  else
    if echo "$err" | grep -qi "RepositoryNotFoundException"; then
      echo "OK: ecr_repository $repo absent"
    else
      block "ecr_repository $repo check failed: $err"
    fi
  fi
}

check_kms_alias() {
  local alias="alias/${NAME}-signing"
  local err key_id
  if err=$("${AWS_BASE[@]}" kms describe-key --key-id "$alias" 2>&1); then
    key_id=$("${AWS_BASE[@]}" kms describe-key --key-id "$alias" --query KeyMetadata.KeyId --output text 2>&1) || key_id="<key-id-lookup-failed>"
    if in_state "aws_kms_alias.signing"; then
      echo "MANAGED: kms_alias $alias already in state"
    else
      block "kms_alias $alias exists; confirm ownership before bootstrap; if confirmed, import with: terraform -chdir=bootstrap import aws_kms_key.signing $key_id && terraform -chdir=bootstrap import aws_kms_alias.signing $alias"
    fi
  else
    if echo "$err" | grep -qi "NotFoundException"; then
      echo "OK: kms_alias $alias absent"
    else
      block "kms_alias $alias check failed: $err"
    fi
  fi
}

check_budget() {
  local budget="${NAME}-monthly"
  local err
  if err=$("${AWS_BASE[@]}" budgets describe-budget --account-id "$ACCOUNT_ID" --budget-name "$budget" 2>&1); then
    if in_state "aws_budgets_budget.monthly[0]"; then
      echo "MANAGED: budget $budget already in state"
    else
      block "budget $budget exists; confirm ownership before bootstrap; if confirmed, import with: terraform -chdir=bootstrap import 'aws_budgets_budget.monthly[0]' $ACCOUNT_ID:$budget"
    fi
  else
    if echo "$err" | grep -qi "NotFoundException"; then
      echo "OK: budget $budget absent"
    else
      block "budget $budget check failed: $err"
    fi
  fi
}

check_oidc_provider() {
  local list_err arn
  if ! list_err=$("${AWS_BASE[@]}" iam list-open-id-connect-providers --output json 2>&1); then
    block "oidc_provider list failed: $list_err"
    return
  fi
  arn=$(echo "$list_err" | grep -o '"Arn": *"[^"]*token.actions.githubusercontent.com"' | sed -E 's/.*"(arn:[^"]+)"/\1/' | head -n1 || true)
  if [[ -z "$arn" ]]; then
    echo "OK: OIDC provider absent; bootstrap will create it"
    return
  fi
  local detail
  if ! detail=$("${AWS_BASE[@]}" iam get-open-id-connect-provider --open-id-connect-provider-arn "$arn" --query 'ClientIDList' --output json 2>&1); then
    block "oidc_provider detail fetch failed for $arn: $detail"
    return
  fi
  if echo "$detail" | jq -e 'index("sts.amazonaws.com")' >/dev/null 2>&1; then
    echo "EXTERNAL: OIDC provider present and valid; bootstrap will reference it as a data source (set TF_VAR_oidc_provider_external=true)"
  else
    block "OIDC provider present but audience sts.amazonaws.com missing from ClientIDList; fix manually before bootstrap"
  fi
}

check_s3_bucket
check_iam_role "${NAME}-plan-reader" "aws_iam_role.plan_reader"
check_iam_role "${NAME}-deployer" "aws_iam_role.deployer"
check_iam_role "${NAME}-publisher" "aws_iam_role.publisher"
check_ecr_repo "${NAME}/placeholder"
check_ecr_repo "${NAME}/orbit-api"
check_ecr_repo "${NAME}/orbit-worker"
check_ecr_repo "${NAME}/orbit-clickhouse"
check_ecr_repo "${NAME}/mirror/clickhouse"
check_ecr_repo "${NAME}/mirror/redis"
check_kms_alias
if [[ -n "$ACCOUNT_ID" ]]; then
  check_budget
else
  echo "SKIP: budget check skipped; caller identity lookup failed above"
fi
check_oidc_provider

echo
if [[ "$BLOCKED" -eq 1 ]]; then
  echo "== preflight FAILED: unresolved BLOCK(s) above =="
  exit 2
fi
echo "== preflight OK: no conflicts; safe to run bootstrap =="
exit 0
