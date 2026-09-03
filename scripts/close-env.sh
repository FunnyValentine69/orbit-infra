#!/usr/bin/env bash
# close-env.sh <env_id> — Stage 1 of the two-stage close (ADR 0006).
#
# lease -> closing (CAS) -> persist/merge manifest -> discover and scale every
# ECS service to 0 -> terraform destroy (up to 3 retries) -> wait for task
# definitions to become INACTIVE, request deletion -> re-query the tag and
# service-specific inventories -> leave the lease `closing` with state intact.
# Stage 2 (the sweeper) confirms task-definition deletion, removes state
# versions, and transitions the lease to `closed`. Any stage-1 failure sets
# cleanup_failed and preserves the manifest/state for retry.
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

# shellcheck disable=SC2329  # Invoked indirectly by the EXIT trap.
cleanup() {
  if [ "$TARGET" = "localstack" ]; then
    rm -f envs/preview/backend_override.tf
  fi
}
trap cleanup EXIT

OPERATOR_CIDR="${OPERATOR_CIDR:-$(curl -s https://checkip.amazonaws.com | awk '{print $1"/32"}')}"

# --- terraform plumbing, mirroring the current Makefile targets ---

tf_init() {
  if [ "$TARGET" = "localstack" ]; then
    sed "s/ENV_ID_PLACEHOLDER/$ENV_ID/" envs/preview/localstack.backend_override.tf.example > envs/preview/backend_override.tf
    TF_DATA_DIR=".terraform-localstack-$ENV_ID" terraform -chdir=envs/preview init -reconfigure -input=false >&2
  else
    rm -f envs/preview/backend_override.tf
    local backend_hcl="$REPO_ROOT/envs/preview/backend.aws.hcl"
    [ -f "$backend_hcl" ] || backend_hcl="$REPO_ROOT/envs/preview/backend.aws.hcl.example"
    terraform -chdir=envs/preview init -reconfigure -backend-config="$backend_hcl" -backend-config="key=envs/preview/${ENV_ID}.tfstate" >&2
  fi
}

# tf_raw: for subcommands that take no -var flags (state, output, show).
tf_raw() {
  if [ "$TARGET" = "localstack" ]; then
    TF_DATA_DIR=".terraform-localstack-$ENV_ID" terraform -chdir=envs/preview "$@"
  else
    terraform -chdir=envs/preview "$@"
  fi
}

# tf: for subcommands that take -var flags (destroy).
tf() {
  if [ "$TARGET" = "localstack" ]; then
    TF_DATA_DIR=".terraform-localstack-$ENV_ID" terraform -chdir=envs/preview "$@" -var target="$TARGET" -var env_id="$ENV_ID" -var operator_cidr="$OPERATOR_CIDR"
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

resource_ids() {
  local resource_type="$1"
  local field="$2"
  jq -c --arg resource_type "$resource_type" --arg field "$field" \
    '[.[] | select(.type == $resource_type) | .values[$field] | select(type == "string" and length > 0)] | unique' \
    <<< "$resource_values_json"
}

echo "== close-env.sh: env_id=$ENV_ID target=$TARGET =="

# --- lease -> closing (CAS); retain any prior manifest on a resumed close ---
current_status=""
existing_manifest="{}"
if get_out=$("$LEASE_SH" get "$ENV_ID" 2>/dev/null); then
  current_status=$(jq -r '.status' <<< "$get_out")
  existing_manifest=$(jq -c '.manifest // {}' <<< "$get_out")
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

# --- manifest: Terraform state plus service-specific inventories ---
state_list=$(tf_raw state list 2>/dev/null || true)
if state_json=$(tf_raw show -json 2>/dev/null); then
  resource_values_json=$(jq -c '[(.values.root_module? // {}) | recurse(.child_modules[]?) | .resources[]?]' <<< "$state_json")
else
  resource_values_json="[]"
fi

task_definition_arns=$(resource_ids aws_ecs_task_definition arn)
cluster_arns=$(resource_ids aws_ecs_cluster arn)
vpc_ids=$(resource_ids aws_vpc id)
subnet_ids=$(resource_ids aws_subnet id)
security_group_ids=$(resource_ids aws_security_group id)
vpc_endpoint_ids=$(resource_ids aws_vpc_endpoint id)
load_balancer_arns=$(resource_ids aws_lb arn)
target_group_arns=$(resource_ids aws_lb_target_group arn)
s3_bucket_names=$(resource_ids aws_s3_bucket bucket)
secret_arns=$(resource_ids aws_secretsmanager_secret arn)
log_group_names=$(resource_ids aws_cloudwatch_log_group name)
cloud_map_namespace_ids=$(resource_ids aws_service_discovery_private_dns_namespace id)
cloud_map_service_ids=$(resource_ids aws_service_discovery_service id)
sns_topic_arns=$(resource_ids aws_sns_topic arn)
alarm_names=$(resource_ids aws_cloudwatch_metric_alarm alarm_name)
iam_role_names=$(resource_ids aws_iam_role name)

tag_inventory_status="ok"
tag_inventory_json="[]"
if tag_out=$(aws_cmd resourcegroupstaggingapi get-resources --tag-filters "Key=env_id,Values=$ENV_ID" --output json 2>&1); then
  tag_inventory_json=$(jq -c '.ResourceTagMappingList // []' <<< "$tag_out")
else
  tag_inventory_status="unsupported"
  echo "close-env.sh: resourcegroupstaggingapi unavailable: $tag_out" >&2
fi

prior_cluster_arns=$(jq -c '[.service_inventory.ecs_clusters[]?.cluster_arn] | unique' <<< "$existing_manifest")
tagged_cluster_arns=$(jq -c '[.[]?.ResourceARN | select(test(":cluster/"))] | unique' <<< "$tag_inventory_json")
cluster_arns=$(jq -cn \
  --argjson state "$cluster_arns" \
  --argjson prior "$prior_cluster_arns" \
  --argjson tagged "$tagged_cluster_arns" \
  '$state + $prior + $tagged | unique')

ecs_clusters="[]"
while IFS= read -r cluster_arn; do
  [ -z "$cluster_arn" ] && continue
  if ! services_out=$(aws_cmd ecs list-services --cluster "$cluster_arn" --output json 2>&1); then
    fail "could not list ECS services for $cluster_arn: $services_out"
  fi
  if ! running_tasks_out=$(aws_cmd ecs list-tasks --cluster "$cluster_arn" --desired-status RUNNING --output json 2>&1); then
    fail "could not list running ECS tasks for $cluster_arn: $running_tasks_out"
  fi
  if ! pending_tasks_out=$(aws_cmd ecs list-tasks --cluster "$cluster_arn" --desired-status PENDING --output json 2>&1); then
    fail "could not list pending ECS tasks for $cluster_arn: $pending_tasks_out"
  fi
  service_arns=$(jq -c '.serviceArns // []' <<< "$services_out")
  task_arns=$(jq -cn --argjson running "$(jq -c '.taskArns // []' <<< "$running_tasks_out")" \
    --argjson pending "$(jq -c '.taskArns // []' <<< "$pending_tasks_out")" '$running + $pending | unique')
  ecs_clusters=$(jq -c --arg cluster_arn "$cluster_arn" --argjson service_arns "$service_arns" --argjson task_arns "$task_arns" \
    '. + [{cluster_arn: $cluster_arn, service_arns: $service_arns, task_arns: $task_arns}]' <<< "$ecs_clusters")
done < <(jq -r '.[]' <<< "$cluster_arns")

manifest_json=$(jq -cn \
  --argjson old "$existing_manifest" \
  --arg env_id "$ENV_ID" \
  --arg target "$TARGET" \
  --argjson state_resources "$(jq -R -s -c 'split("\n") | map(select(length > 0))' <<< "$state_list")" \
  --argjson task_definition_arns "$task_definition_arns" \
  --arg tagging_inventory_status "$tag_inventory_status" \
  --argjson tagging_inventory "$tag_inventory_json" \
  --argjson ecs_clusters "$ecs_clusters" \
  --argjson vpc_ids "$vpc_ids" \
  --argjson subnet_ids "$subnet_ids" \
  --argjson security_group_ids "$security_group_ids" \
  --argjson vpc_endpoint_ids "$vpc_endpoint_ids" \
  --argjson load_balancer_arns "$load_balancer_arns" \
  --argjson target_group_arns "$target_group_arns" \
  --argjson s3_bucket_names "$s3_bucket_names" \
  --argjson secret_arns "$secret_arns" \
  --argjson log_group_names "$log_group_names" \
  --argjson cloud_map_namespace_ids "$cloud_map_namespace_ids" \
  --argjson cloud_map_service_ids "$cloud_map_service_ids" \
  --argjson sns_topic_arns "$sns_topic_arns" \
  --argjson alarm_names "$alarm_names" \
  --argjson iam_role_names "$iam_role_names" '
  def union(old; new): ((old // []) + new | unique);
  def merge_clusters(old; new):
    ((old // []) + new
      | group_by(.cluster_arn)
      | map({
          cluster_arn: .[0].cluster_arn,
          service_arns: ([.[].service_arns[]?] | unique),
          task_arns: ([.[].task_arns[]?] | unique)
        }));
  {
    env_id: $env_id,
    target: $target,
    state_resources: union($old.state_resources; $state_resources),
    task_definition_arns: union($old.task_definition_arns; $task_definition_arns),
    tagging_inventory_status: (
      if $old.tagging_inventory_status == "ok" or $tagging_inventory_status == "ok"
      then "ok"
      else "unsupported"
      end
    ),
    tagging_inventory: (($old.tagging_inventory // []) + $tagging_inventory | unique_by(.ResourceARN)),
    service_inventory: {
      ecs_clusters: merge_clusters($old.service_inventory.ecs_clusters; $ecs_clusters),
      vpc_ids: union($old.service_inventory.vpc_ids; $vpc_ids),
      subnet_ids: union($old.service_inventory.subnet_ids; $subnet_ids),
      security_group_ids: union($old.service_inventory.security_group_ids; $security_group_ids),
      vpc_endpoint_ids: union($old.service_inventory.vpc_endpoint_ids; $vpc_endpoint_ids),
      load_balancer_arns: union($old.service_inventory.load_balancer_arns; $load_balancer_arns),
      target_group_arns: union($old.service_inventory.target_group_arns; $target_group_arns),
      s3_bucket_names: union($old.service_inventory.s3_bucket_names; $s3_bucket_names),
      secret_arns: union($old.service_inventory.secret_arns; $secret_arns),
      log_group_names: union($old.service_inventory.log_group_names; $log_group_names),
      cloud_map_namespace_ids: union($old.service_inventory.cloud_map_namespace_ids; $cloud_map_namespace_ids),
      cloud_map_service_ids: union($old.service_inventory.cloud_map_service_ids; $cloud_map_service_ids),
      sns_topic_arns: union($old.service_inventory.sns_topic_arns; $sns_topic_arns),
      alarm_names: union($old.service_inventory.alarm_names; $alarm_names),
      iam_role_names: union($old.service_inventory.iam_role_names; $iam_role_names)
    }
  }') || fail "could not build cleanup manifest"

manifest_file=$(mktemp)
printf '%s\n' "$manifest_json" > "$manifest_file"
"$LEASE_SH" set-manifest "$ENV_ID" "$manifest_file" >/dev/null \
  || fail "set-manifest failed for $ENV_ID"
rm -f "$manifest_file"

# --- scale every service discovered from the environment cluster to 0 ---
while IFS=$'\t' read -r cluster_arn service_arn; do
  [ -z "$service_arn" ] && continue
  echo "scaling $service_arn to 0"
  aws_cmd ecs update-service --cluster "$cluster_arn" --service "$service_arn" --desired-count 0 >/dev/null \
    || fail "failed to scale $service_arn to 0"
  aws_cmd ecs wait services-stable --cluster "$cluster_arn" --services "$service_arn" \
    || fail "$service_arn did not reach stable at 0"
done < <(jq -r '.service_inventory.ecs_clusters[] | .cluster_arn as $cluster | .service_arns[]? | [$cluster, .] | @tsv' <<< "$manifest_json")

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

# --- task definitions: wait for deregistration, request async deletion ---
while IFS= read -r arn; do
  [ -z "$arn" ] && continue
  status="ACTIVE"
  for _ in $(seq 1 20); do
    if describe_out=$(aws_cmd ecs describe-task-definition --task-definition "$arn" --output json 2>&1); then
      status=$(jq -r '.taskDefinition.status // "UNKNOWN"' <<< "$describe_out")
    elif grep -qiE 'ClientException|not found|does not exist' <<< "$describe_out"; then
      status="DELETED"
    else
      fail "DescribeTaskDefinition failed for $arn: $describe_out"
    fi
    case "$status" in
      INACTIVE|DELETE_IN_PROGRESS|DELETED) break ;;
      ACTIVE) sleep 3 ;;
      *) fail "unexpected task-definition status '$status' for $arn" ;;
    esac
  done
  [ "$status" != "ACTIVE" ] || fail "task definition did not become INACTIVE: $arn"

  if [ "$status" = "INACTIVE" ]; then
    if delete_out=$(aws_cmd ecs delete-task-definitions --task-definitions "$arn" 2>&1); then
      echo "requested task-definition deletion: $arn"
    elif grep -qi "not currently supported by LocalStack" <<< "$delete_out"; then
      echo "close-env.sh: DeleteTaskDefinitions unsupported on LocalStack; task definition remains INACTIVE" >&2
    else
      fail "DeleteTaskDefinitions failed for $arn: $delete_out"
    fi
  fi

  if describe_out=$(aws_cmd ecs describe-task-definition --task-definition "$arn" --output json 2>&1); then
    status=$(jq -r '.taskDefinition.status // "UNKNOWN"' <<< "$describe_out")
    case "$status" in
      INACTIVE|DELETE_IN_PROGRESS) ;;
      *) fail "task definition returned to unexpected status '$status': $arn" ;;
    esac
  elif ! grep -qiE 'ClientException|not found|does not exist' <<< "$describe_out"; then
    fail "post-delete DescribeTaskDefinition failed for $arn: $describe_out"
  fi
done < <(jq -r '.task_definition_arns[]' <<< "$manifest_json")

# --- re-query the full tag inventory ---
if tag_out=$(aws_cmd resourcegroupstaggingapi get-resources --tag-filters "Key=env_id,Values=$ENV_ID" --output json 2>&1); then
  remaining_tagged=$(jq -c '.ResourceTagMappingList // []' <<< "$tag_out")
  [ "$remaining_tagged" = "[]" ] \
    || fail "tag inventory still contains resources for env_id=$ENV_ID: $remaining_tagged"
elif [ "$(jq -r '.tagging_inventory_status' <<< "$manifest_json")" = "ok" ]; then
  fail "could not re-query resourcegroupstaggingapi: $tag_out"
else
  echo "close-env.sh: resourcegroupstaggingapi remains unavailable; using service-specific inventory checks" >&2
fi

# --- tag-filter checks catch resources not present in a partial state ---
remaining=$(aws_cmd ec2 describe-vpcs --filters "Name=tag:env_id,Values=$ENV_ID" --output json | jq -c '.Vpcs // []')
[ "$remaining" = "[]" ] || fail "VPCs remain tagged env_id=$ENV_ID: $remaining"
remaining=$(aws_cmd ec2 describe-subnets --filters "Name=tag:env_id,Values=$ENV_ID" --output json | jq -c '.Subnets // []')
[ "$remaining" = "[]" ] || fail "subnets remain tagged env_id=$ENV_ID: $remaining"
remaining=$(aws_cmd ec2 describe-security-groups --filters "Name=tag:env_id,Values=$ENV_ID" --output json | jq -c '.SecurityGroups // []')
[ "$remaining" = "[]" ] || fail "security groups remain tagged env_id=$ENV_ID: $remaining"
remaining=$(aws_cmd ec2 describe-vpc-endpoints --filters "Name=tag:env_id,Values=$ENV_ID" --output json | jq -c '.VpcEndpoints // []')
[ "$remaining" = "[]" ] || fail "VPC endpoints remain tagged env_id=$ENV_ID: $remaining"

# Re-query the exact EC2 identifiers too, so a removed env_id tag cannot hide
# a resource captured before destroy.
check_ec2_inventory_absent() {
  local label="$1"
  local manifest_key="$2"
  local response_key="$3"
  local subcommand="$4"
  local id_flag="$5"
  local id
  local out
  local found

  while IFS= read -r id; do
    [ -z "$id" ] && continue
    if out=$(aws_cmd ec2 "$subcommand" "$id_flag" "$id" --output json 2>&1); then
      found=$(jq -c --arg response_key "$response_key" '.[$response_key] // []' <<< "$out")
      [ "$found" = "[]" ] || fail "$label remains: $id"
    elif ! grep -qiE 'Invalid.*NotFound|not found|does not exist' <<< "$out"; then
      fail "could not prove $label absent ($id): $out"
    fi
  done < <(jq -r --arg manifest_key "$manifest_key" '.service_inventory[$manifest_key][]' <<< "$manifest_json")
}

check_ec2_inventory_absent "VPC" vpc_ids Vpcs describe-vpcs --vpc-ids
check_ec2_inventory_absent "subnet" subnet_ids Subnets describe-subnets --subnet-ids
check_ec2_inventory_absent "security group" security_group_ids SecurityGroups describe-security-groups --group-ids
check_ec2_inventory_absent "VPC endpoint" vpc_endpoint_ids VpcEndpoints describe-vpc-endpoints --vpc-endpoint-ids

# --- re-query every service-specific inventory captured in the manifest ---
while IFS= read -r cluster_arn; do
  [ -z "$cluster_arn" ] && continue
  if cluster_out=$(aws_cmd ecs describe-clusters --clusters "$cluster_arn" --output json 2>&1); then
    active_clusters=$(jq -c '[.clusters[]? | select(.status != "INACTIVE")]' <<< "$cluster_out")
    [ "$active_clusters" = "[]" ] || fail "ECS cluster remains active: $active_clusters"
  elif ! grep -qiE 'ClusterNotFound|not found' <<< "$cluster_out"; then
    fail "could not re-query ECS cluster $cluster_arn: $cluster_out"
  fi

  if services_out=$(aws_cmd ecs list-services --cluster "$cluster_arn" --output json 2>&1); then
    remaining=$(jq -c '.serviceArns // []' <<< "$services_out")
    [ "$remaining" = "[]" ] || fail "ECS services remain in $cluster_arn: $remaining"
  elif ! grep -qiE 'ClusterNotFound|not found' <<< "$services_out"; then
    fail "could not re-query ECS services for $cluster_arn: $services_out"
  fi

  if tasks_out=$(aws_cmd ecs list-tasks --cluster "$cluster_arn" --output json 2>&1); then
    remaining=$(jq -c '.taskArns // []' <<< "$tasks_out")
    [ "$remaining" = "[]" ] || fail "ECS tasks remain in $cluster_arn: $remaining"
  elif ! grep -qiE 'ClusterNotFound|not found' <<< "$tasks_out"; then
    fail "could not re-query ECS tasks for $cluster_arn: $tasks_out"
  fi
done < <(jq -r '.service_inventory.ecs_clusters[].cluster_arn' <<< "$manifest_json")

while IFS= read -r arn; do
  [ -z "$arn" ] && continue
  if out=$(aws_cmd elbv2 describe-load-balancers --load-balancer-arns "$arn" --output json 2>&1); then
    remaining=$(jq -c '.LoadBalancers // []' <<< "$out")
    [ "$remaining" = "[]" ] || fail "load balancer remains: $arn"
  elif ! grep -qiE 'LoadBalancerNotFound|not found' <<< "$out"; then
    fail "could not re-query load balancer $arn: $out"
  fi
done < <(jq -r '.service_inventory.load_balancer_arns[]' <<< "$manifest_json")

while IFS= read -r arn; do
  [ -z "$arn" ] && continue
  if out=$(aws_cmd elbv2 describe-target-groups --target-group-arns "$arn" --output json 2>&1); then
    remaining=$(jq -c '.TargetGroups // []' <<< "$out")
    [ "$remaining" = "[]" ] || fail "target group remains: $arn"
  elif ! grep -qiE 'TargetGroupNotFound|not found' <<< "$out"; then
    fail "could not re-query target group $arn: $out"
  fi
done < <(jq -r '.service_inventory.target_group_arns[]' <<< "$manifest_json")

while IFS= read -r bucket; do
  [ -z "$bucket" ] && continue
  if out=$(aws_cmd s3api head-bucket --bucket "$bucket" 2>&1); then
    fail "S3 bucket remains: $bucket"
  elif ! grep -qiE 'NoSuchBucket|Not Found|404' <<< "$out"; then
    fail "could not prove S3 bucket absent ($bucket): $out"
  fi
done < <(jq -r '.service_inventory.s3_bucket_names[]' <<< "$manifest_json")

while IFS= read -r arn; do
  [ -z "$arn" ] && continue
  if out=$(aws_cmd secretsmanager describe-secret --secret-id "$arn" --output json 2>&1); then
    fail "Secrets Manager secret remains: $arn"
  elif ! grep -qiE 'ResourceNotFound|not found' <<< "$out"; then
    fail "could not prove secret absent ($arn): $out"
  fi
done < <(jq -r '.service_inventory.secret_arns[]' <<< "$manifest_json")

while IFS= read -r name; do
  [ -z "$name" ] && continue
  out=$(aws_cmd logs describe-log-groups --log-group-name-prefix "$name" --output json) \
    || fail "could not re-query log group $name"
  remaining=$(jq -c --arg name "$name" '[.logGroups[]? | select(.logGroupName == $name)]' <<< "$out")
  [ "$remaining" = "[]" ] || fail "CloudWatch log group remains: $name"
done < <(jq -r '.service_inventory.log_group_names[]' <<< "$manifest_json")

while IFS= read -r id; do
  [ -z "$id" ] && continue
  if out=$(aws_cmd servicediscovery get-namespace --id "$id" --output json 2>&1); then
    fail "Cloud Map namespace remains: $id"
  elif ! grep -qiE 'NamespaceNotFound|not found' <<< "$out"; then
    fail "could not prove Cloud Map namespace absent ($id): $out"
  fi
done < <(jq -r '.service_inventory.cloud_map_namespace_ids[]' <<< "$manifest_json")

while IFS= read -r id; do
  [ -z "$id" ] && continue
  if out=$(aws_cmd servicediscovery get-service --id "$id" --output json 2>&1); then
    fail "Cloud Map service remains: $id"
  elif ! grep -qiE 'ServiceNotFound|not found' <<< "$out"; then
    fail "could not prove Cloud Map service absent ($id): $out"
  fi
done < <(jq -r '.service_inventory.cloud_map_service_ids[]' <<< "$manifest_json")

while IFS= read -r arn; do
  [ -z "$arn" ] && continue
  if out=$(aws_cmd sns get-topic-attributes --topic-arn "$arn" --output json 2>&1); then
    fail "SNS topic remains: $arn"
  elif ! grep -qiE 'NotFound|not found' <<< "$out"; then
    fail "could not prove SNS topic absent ($arn): $out"
  fi
done < <(jq -r '.service_inventory.sns_topic_arns[]' <<< "$manifest_json")

while IFS= read -r name; do
  [ -z "$name" ] && continue
  out=$(aws_cmd cloudwatch describe-alarms --alarm-names "$name" --output json) \
    || fail "could not re-query CloudWatch alarm $name"
  remaining=$(jq -c '.MetricAlarms // []' <<< "$out")
  [ "$remaining" = "[]" ] || fail "CloudWatch alarm remains: $name"
done < <(jq -r '.service_inventory.alarm_names[]' <<< "$manifest_json")

while IFS= read -r name; do
  [ -z "$name" ] && continue
  if out=$(aws_cmd iam get-role --role-name "$name" --output json 2>&1); then
    fail "IAM role remains: $name"
  elif ! grep -qiE 'NoSuchEntity|not found' <<< "$out"; then
    fail "could not prove IAM role absent ($name): $out"
  fi
done < <(jq -r '.service_inventory.iam_role_names[]' <<< "$manifest_json")

echo "close-env.sh: $ENV_ID stage 1 complete; lease remains 'closing' for the sweeper"
exit 0
