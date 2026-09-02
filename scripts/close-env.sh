#!/usr/bin/env bash
# close-env.sh <env_id> — Stage 1 of the two-stage close (ADR 0006).
#
# lease -> closing (CAS) -> build+store manifest -> scale ECS services to
# 0 -> terraform destroy (up to 3 retries) -> DeleteTaskDefinitions on the
# manifest's task ARNs -> cost-bearing-zero check -> closed (state
# versions pruned) if every task definition is gone, else left `closing`
# for stage 2 (the sweeper) to finish. Any failure along the way sets
# cleanup_failed with the error, keeping state intact for retry.
#
# Env: TARGET (aws|localstack, required), ENV_ID or $1, LEASE_BUCKET
# (passed through to lease.sh), AWS_ENDPOINT_URL (LocalStack only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEASE_SH="$SCRIPT_DIR/lease.sh"

ENV_ID="${1:-${ENV_ID:-}}"
TARGET="${TARGET:-aws}"
LEASE_BUCKET="${LEASE_BUCKET:-orbit-infra-79s5rw-tfstate}"
export LEASE_BUCKET

if [ -z "$ENV_ID" ]; then
  echo "close-env.sh: env_id required (arg 1 or \$ENV_ID)" >&2
  exit 2
fi

cd "$REPO_ROOT"

OPERATOR_CIDR="${OPERATOR_CIDR:-$(curl -s https://checkip.amazonaws.com | awk '{print $1"/32"}')}"

# --- terraform plumbing, mirroring the Makefile's plan/apply/destroy targets ---

tf_init() {
  if [ "$TARGET" = "localstack" ]; then
    sed "s/ENV_ID_PLACEHOLDER/$ENV_ID/" envs/preview/localstack.backend_override.tf.example > envs/preview/backend_override.tf
    TF_DATA_DIR=.terraform-localstack terraform -chdir=envs/preview init -reconfigure -input=false >&2
  else
    rm -f envs/preview/backend_override.tf
    local backend_hcl="envs/preview/backend.aws.hcl"
    [ -f "$backend_hcl" ] || backend_hcl="envs/preview/backend.aws.hcl.example"
    terraform -chdir=envs/preview init -reconfigure -backend-config="$backend_hcl" -backend-config="key=envs/preview/${ENV_ID}.tfstate" >&2
  fi
}

# tf_raw: for subcommands that take no -var flags (state, output).
tf_raw() {
  if [ "$TARGET" = "localstack" ]; then
    TF_DATA_DIR=.terraform-localstack terraform -chdir=envs/preview "$@"
  else
    terraform -chdir=envs/preview "$@"
  fi
}

# tf: for subcommands that take -var flags (plan, apply, destroy).
tf() {
  if [ "$TARGET" = "localstack" ]; then
    TF_DATA_DIR=.terraform-localstack terraform -chdir=envs/preview "$@" -var target="$TARGET" -var env_id="$ENV_ID" -var operator_cidr="$OPERATOR_CIDR"
  else
    terraform -chdir=envs/preview "$@" -var target="$TARGET" -var env_id="$ENV_ID" -var operator_cidr="$OPERATOR_CIDR"
  fi
}

aws_cmd() { aws "$@"; }

fail() {
  local msg="$1"
  echo "close-env.sh: $msg" >&2
  "$LEASE_SH" transition "$ENV_ID" closing cleanup_failed --error "$msg" || true
  exit 1
}

echo "== close-env.sh: env_id=$ENV_ID target=$TARGET =="

# --- lease -> closing (CAS) ---
current_status=""
if get_out=$("$LEASE_SH" get "$ENV_ID" 2>/dev/null); then
  current_status=$(echo "$get_out" | jq -r '.status')
fi

case "$current_status" in
  closing)
    echo "lease already closing; resuming stage 1"
    ;;
  closed)
    echo "lease already closed; nothing to do"
    exit 0
    ;;
  open|cleanup_failed)
    "$LEASE_SH" transition "$ENV_ID" "$current_status" closing >/dev/null
    ;;
  "")
    echo "close-env.sh: no lease for $ENV_ID; nothing to close" >&2
    exit 0
    ;;
  *)
    echo "close-env.sh: unexpected lease status '$current_status' for $ENV_ID" >&2
    exit 2
    ;;
esac

tf_init

# --- build manifest: state list + ECS task-definition ARNs + tag inventory ---
state_list=$(tf_raw state list 2>/dev/null || true)
task_def_arns=""
if echo "$state_list" | grep -qE '(^|\.)aws_ecs_task_definition\.'; then
  task_def_arns=$(echo "$state_list" | grep -E '(^|\.)aws_ecs_task_definition\.' | while read -r addr; do
    tf_raw state show "$addr" 2>/dev/null | grep -E '^\s*arn\s*=' | head -1 | sed -E 's/.*"(arn:[^"]+)".*/\1/'
  done)
fi

tag_inventory_status="ok"
tag_inventory_json="[]"
if tag_out=$(aws_cmd resourcegroupstaggingapi get-resources --tag-filters "Key=env_id,Values=$ENV_ID" --output json 2>&1); then
  tag_inventory_json=$(echo "$tag_out" | jq -c '.ResourceTagMappingList // []')
else
  tag_inventory_status="unsupported"
  echo "close-env.sh: resourcegroupstaggingapi unavailable: $tag_out" >&2
fi

manifest_file=$(mktemp)
jq -n \
  --arg env_id "$ENV_ID" \
  --arg target "$TARGET" \
  --argjson state_resources "$(echo "$state_list" | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
  --argjson task_definition_arns "$(echo "$task_def_arns" | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
  --arg tagging_inventory_status "$tag_inventory_status" \
  --argjson tagging_inventory "$tag_inventory_json" \
  '{env_id: $env_id, target: $target, state_resources: $state_resources, task_definition_arns: $task_definition_arns, tagging_inventory_status: $tagging_inventory_status, tagging_inventory: $tagging_inventory}' \
  > "$manifest_file"

"$LEASE_SH" set-manifest "$ENV_ID" "$manifest_file" >/dev/null \
  || fail "set-manifest failed for $ENV_ID"
rm -f "$manifest_file"

# --- scale ECS services to 0, wait services-stable ---
cluster_arn=$(tf_raw output -raw ecs_cluster_arn 2>/dev/null || true)
if [ -n "$cluster_arn" ]; then
  for svc_output in api_service_name worker_service_name; do
    svc_name=$(tf_raw output -raw "$svc_output" 2>/dev/null || true)
    [ -z "$svc_name" ] && continue
    echo "scaling $svc_name to 0"
    aws_cmd ecs update-service --cluster "$cluster_arn" --service "$svc_name" --desired-count 0 >/dev/null \
      || fail "failed to scale $svc_name to 0"
    aws_cmd ecs wait services-stable --cluster "$cluster_arn" --services "$svc_name" \
      || fail "$svc_name did not reach stable at 0"
  done
else
  echo "close-env.sh: no ecs_cluster_arn in outputs (state may already be partially destroyed); skipping scale-down" >&2
fi

# --- terraform destroy, up to 3 retries ---
destroy_ok=0
for attempt in 1 2 3; do
  echo "terraform destroy attempt $attempt/3"
  if tf destroy -auto-approve; then
    destroy_ok=1
    break
  fi
  echo "destroy attempt $attempt failed" >&2
done
[ "$destroy_ok" = "1" ] || fail "terraform destroy failed after 3 attempts"

# --- DeleteTaskDefinitions on manifest ARNs ---
task_defs_gone=1
if [ -n "$task_def_arns" ]; then
  while read -r arn; do
    [ -z "$arn" ] && continue
    if del_out=$(aws_cmd ecs delete-task-definitions --task-definitions "$arn" 2>&1); then
      :
    elif echo "$del_out" | grep -qi "not currently supported by LocalStack"; then
      echo "close-env.sh: DeleteTaskDefinitions unsupported on LocalStack; leaving task definitions in place" >&2
      task_defs_gone=0
    else
      echo "close-env.sh: DeleteTaskDefinitions failed for $arn: $del_out" >&2
      task_defs_gone=0
    fi
  done <<< "$task_def_arns"
fi

# --- cost-bearing zero check ---
remaining_vpcs=$(aws_cmd ec2 describe-vpcs --filters "Name=tag:env_id,Values=$ENV_ID" --output json | jq -c '.Vpcs // []')
if [ "$remaining_vpcs" != "[]" ]; then
  fail "cost-bearing check failed: VPCs remain tagged env_id=$ENV_ID: $remaining_vpcs"
fi

# --- stage-2 finalize when task definitions are confirmed gone; else leave closing ---
if [ "$task_defs_gone" = "1" ]; then
  "$LEASE_SH" transition "$ENV_ID" closing closed >/dev/null \
    || fail "final transition to closed failed for $ENV_ID"
  echo "close-env.sh: $ENV_ID closed"
else
  echo "close-env.sh: $ENV_ID left in 'closing'; task definitions not yet confirmed deleted (stage 2/sweeper finishes this)"
fi

exit 0
