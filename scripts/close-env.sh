#!/usr/bin/env bash
# close-env.sh — stage 1 of ADR 0006's two-stage preview close.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEASE_SH="${LEASE_SH:-$SCRIPT_DIR/lease.sh}"
AWS_CLI_SH="${AWS_CLI_SH:-$SCRIPT_DIR/aws-cli.sh}"
CLEANUP_VERIFIER_SH="${CLEANUP_VERIFIER_SH:-$SCRIPT_DIR/cleanup-verifier.sh}"

FORCE_RETRY=false
EXPECTED_GENERATION=""
ENV_ID="${ENV_ID:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force-retry)
      FORCE_RETRY=true
      shift
      ;;
    --generation)
      [ "$#" -ge 2 ] || { echo "close-env.sh: --generation requires a value" >&2; exit 2; }
      EXPECTED_GENERATION="$2"
      shift 2
      ;;
    --*)
      echo "close-env.sh: unknown option '$1'" >&2
      exit 2
      ;;
    *)
      if [ -n "$ENV_ID" ] && [ "$ENV_ID" != "$1" ]; then
        echo "close-env.sh: conflicting env_id values" >&2
        exit 2
      fi
      ENV_ID="$1"
      shift
      ;;
  esac
done
TARGET="${TARGET:-}"
LEASE_BUCKET="${LEASE_BUCKET:-orbit-infra-79s5rw-tfstate}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
TAG_REQUERY_OFFSETS="${TAG_REQUERY_OFFSETS:-0 2 4 8 16 30}"
CLEANUP_VERIFY_DEADLINE_SECONDS="${CLEANUP_VERIFY_DEADLINE_SECONDS:-300}"
CLEANUP_VERIFY_BACKOFF="${CLEANUP_VERIFY_BACKOFF:-2 4 8 16 30}"
destroy_image_vars=()
export LEASE_BUCKET TARGET

case "$TARGET" in
  localstack|aws) ;;
  *) echo "close-env.sh: TARGET is required and must be aws or localstack" >&2; exit 2 ;;
esac
if [ -z "$ENV_ID" ]; then
  echo "close-env.sh: env_id required (argument or ENV_ID)" >&2
  exit 2
fi
if [ -n "$EXPECTED_GENERATION" ] && ! [[ "$EXPECTED_GENERATION" =~ ^[1-9][0-9]*$ ]]; then
  echo "close-env.sh: --generation must be a positive integer" >&2
  exit 2
fi
if ! [[ "$CLEANUP_VERIFY_DEADLINE_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "close-env.sh: CLEANUP_VERIFY_DEADLINE_SECONDS must be a nonnegative integer" >&2
  exit 2
fi

if [ -z "${PREVIEW_ROOT:-}" ]; then
  if [ "$TARGET" = localstack ]; then
    PREVIEW_ROOT=".preview-runs/$ENV_ID"
  else
    PREVIEW_ROOT=envs/preview
  fi
fi
export PREVIEW_ROOT

cd "$REPO_ROOT"
OPERATOR_CIDR="${OPERATOR_CIDR:-$(curl -sf --max-time 5 https://checkip.amazonaws.com | awk '{print $1"/32"}')}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

aws_cmd() { "$AWS_CLI_SH" "$@"; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date -u +%s; }

tf_init() {
  if [ "$TARGET" = localstack ]; then
    mkdir -p "$PREVIEW_ROOT"
    sed "s/ENV_ID_PLACEHOLDER/$ENV_ID/" envs/preview/localstack.backend_override.tf.example > "$PREVIEW_ROOT/backend_override.tf"
    TF_DATA_DIR=.terraform-localstack terraform -chdir="$PREVIEW_ROOT" init -reconfigure -input=false >&2
  else
    local backend_hcl="$REPO_ROOT/envs/preview/backend.aws.hcl"
    if [ ! -f "$backend_hcl" ]; then
      echo "close-env.sh: envs/preview/backend.aws.hcl is required; run scripts/write-preview-backend.sh" >&2
      return 1
    fi
    terraform -chdir="$PREVIEW_ROOT" init -reconfigure -input=false \
      -backend-config="$backend_hcl" \
      -backend-config="key=envs/preview/${ENV_ID}.tfstate" >&2
  fi
}

tf_raw() {
  if [ "$TARGET" = localstack ]; then
    TF_DATA_DIR=.terraform-localstack terraform -chdir="$PREVIEW_ROOT" "$@"
  else
    terraform -chdir="$PREVIEW_ROOT" "$@"
  fi
}

tf_destroy() {
  if [ "$TARGET" = localstack ]; then
    TF_DATA_DIR=.terraform-localstack terraform -chdir="$PREVIEW_ROOT" destroy \
      -auto-approve -var target="$TARGET" -var env_id="$ENV_ID" -var operator_cidr="$OPERATOR_CIDR" -var region="$AWS_REGION"
  else
    terraform -chdir="$PREVIEW_ROOT" destroy \
      -auto-approve -var target="$TARGET" -var env_id="$ENV_ID" -var operator_cidr="$OPERATOR_CIDR" -var region="$AWS_REGION" \
      "${destroy_image_vars[@]}"
  fi
}

fail() {
  local message="$1"
  echo "close-env.sh: $message" >&2
  "$LEASE_SH" transition "$ENV_ID" closing cleanup_failed --error "$message" >/dev/null \
    || echo "close-env.sh: could not record cleanup_failed for $ENV_ID (lease may still read closing)" >&2
  exit 1
}

persist_manifest() {
  local manifest_file="$tmp_dir/manifest.json"
  printf '%s\n' "$manifest_json" > "$manifest_file"
  "$LEASE_SH" set-manifest "$ENV_ID" "$manifest_file" >/dev/null \
    || fail "could not persist cleanup manifest"
}

merge_candidate_files() {
  "$CLEANUP_VERIFIER_SH" merge-candidates "$@"
}

normalize_tag_entries() {
  local entries="$1"
  printf '%s\n' "$entries" | "$CLEANUP_VERIFIER_SH" normalize-tags
}

state_candidates() {
  jq -c '
    def c($type; $id; $arn; $parent; $force):
      if ($id | type) == "string" and ($id | length) > 0 then
        {
          resource_type: $type,
          id: $id,
          arn: (if ($arn | type) == "string" and ($arn | length) > 0 then $arn else null end),
          parent_id: (if ($parent | type) == "string" and ($parent | length) > 0 then $parent else null end),
          sources: ["terraform-state"],
          tag_entry: null,
          force_delete: $force
        }
      else empty end;
    [
      .[]
      | .type as $type
      | .values as $v
      | if $type == "aws_vpc" then c("ec2:vpc"; $v.id; null; null; false)
        elif $type == "aws_subnet" then c("ec2:subnet"; $v.id; null; null; false)
        elif $type == "aws_security_group" then c("ec2:security-group"; $v.id; null; null; false)
        elif $type == "aws_vpc_security_group_ingress_rule" or $type == "aws_vpc_security_group_egress_rule" then c("ec2:security-group-rule"; $v.id; null; null; false)
        elif $type == "aws_internet_gateway" then c("ec2:internet-gateway"; $v.id; null; null; false)
        elif $type == "aws_route_table" then c("ec2:route-table"; $v.id; null; null; false)
        elif $type == "aws_vpc_endpoint" then c("ec2:vpc-endpoint"; $v.id; null; null; false)
        elif $type == "aws_lb" then c("elbv2:load-balancer"; $v.arn; $v.arn; null; false)
        elif $type == "aws_lb_target_group" then c("elbv2:target-group"; $v.arn; $v.arn; null; false)
        elif $type == "aws_lb_listener" then c("elbv2:listener"; $v.arn; $v.arn; null; false)
        elif $type == "aws_lb_listener_rule" then c("elbv2:listener-rule"; $v.arn; $v.arn; null; false)
        elif $type == "aws_ecs_cluster" then c("ecs:cluster"; $v.arn; $v.arn; null; false)
        elif $type == "aws_ecs_service" then c("ecs:service"; ($v.arn // $v.id); ($v.arn // $v.id); $v.cluster; false)
        elif $type == "aws_ecs_task_definition" then c("ecs:task-definition"; $v.arn; $v.arn; null; false)
        elif $type == "aws_service_discovery_private_dns_namespace" then c("servicediscovery:namespace"; $v.id; $v.arn; null; false)
        elif $type == "aws_service_discovery_service" then c("servicediscovery:service"; $v.id; $v.arn; null; false)
        elif $type == "aws_cloudwatch_log_group" then c("logs:log-group"; $v.name; $v.arn; null; false)
        elif $type == "aws_secretsmanager_secret" then c("secretsmanager:secret"; $v.arn; $v.arn; null; true)
        elif $type == "aws_s3_bucket" then c("s3:bucket"; $v.bucket; $v.arn; null; false)
        elif $type == "aws_sns_topic" then c("sns:topic"; $v.arn; $v.arn; null; false)
        elif $type == "aws_cloudwatch_metric_alarm" then c("cloudwatch:alarm"; $v.alarm_name; $v.arn; null; false)
        elif $type == "aws_iam_role" then c("iam:role"; $v.name; $v.arn; null; false)
        else empty end
    ]' <<< "$resource_values_json"
}

legacy_manifest_candidates() {
  jq -c '
    def c($type; $id; $arn; $parent; $force):
      if ($id | type) == "string" and ($id | length) > 0 then
        {resource_type:$type,id:$id,arn:$arn,parent_id:$parent,sources:["prior-manifest"],tag_entry:null,force_delete:$force}
      else empty end;
    [
      (.task_definition_arns[]? | c("ecs:task-definition"; .; .; null; false)),
      (.service_inventory.ecs_clusters[]? as $cluster
        | c("ecs:cluster"; $cluster.cluster_arn; $cluster.cluster_arn; null; false)),
      (.service_inventory.ecs_clusters[]? as $cluster
        | $cluster.service_arns[]? | c("ecs:service"; .; .; $cluster.cluster_arn; false)),
      (.service_inventory.ecs_clusters[]? as $cluster
        | $cluster.task_arns[]? | c("ecs:task"; .; .; $cluster.cluster_arn; false)),
      (.service_inventory.vpc_ids[]? | c("ec2:vpc"; .; null; null; false)),
      (.service_inventory.subnet_ids[]? | c("ec2:subnet"; .; null; null; false)),
      (.service_inventory.security_group_ids[]? | c("ec2:security-group"; .; null; null; false)),
      (.service_inventory.security_group_rule_ids[]? | c("ec2:security-group-rule"; .; null; null; false)),
      (.service_inventory.internet_gateway_ids[]? | c("ec2:internet-gateway"; .; null; null; false)),
      (.service_inventory.route_table_ids[]? | c("ec2:route-table"; .; null; null; false)),
      (.service_inventory.vpc_endpoint_ids[]? | c("ec2:vpc-endpoint"; .; null; null; false)),
      (.service_inventory.load_balancer_arns[]? | c("elbv2:load-balancer"; .; .; null; false)),
      (.service_inventory.target_group_arns[]? | c("elbv2:target-group"; .; .; null; false)),
      (.service_inventory.listener_arns[]? | c("elbv2:listener"; .; .; null; false)),
      (.service_inventory.listener_rule_arns[]? | c("elbv2:listener-rule"; .; .; null; false)),
      (.service_inventory.s3_bucket_names[]? | c("s3:bucket"; .; null; null; false)),
      (.service_inventory.secret_arns[]? | c("secretsmanager:secret"; .; .; null; true)),
      (.service_inventory.log_group_names[]? | c("logs:log-group"; .; null; null; false)),
      (.service_inventory.cloud_map_namespace_ids[]? | c("servicediscovery:namespace"; .; null; null; false)),
      (.service_inventory.cloud_map_service_ids[]? | c("servicediscovery:service"; .; null; null; false)),
      (.service_inventory.sns_topic_arns[]? | c("sns:topic"; .; .; null; false)),
      (.service_inventory.alarm_names[]? | c("cloudwatch:alarm"; .; null; null; false)),
      (.service_inventory.iam_role_names[]? | c("iam:role"; .; null; null; false))
    ]' <<< "$existing_manifest"
}

discover_ecs_candidates() {
  local base_candidates="$1"
  local discovered='[]' cluster service_out running_out pending_out services tasks service task
  while IFS= read -r cluster; do
    [ -n "$cluster" ] || continue
    if ! service_out="$(aws_cmd ecs list-services --cluster "$cluster" --output json 2>&1)"; then
      if grep -qiE 'ClusterNotFound|not found|does not exist' <<< "$service_out"; then
        continue
      fi
      fail "could not discover ECS services for $cluster: $service_out"
    fi
    if ! running_out="$(aws_cmd ecs list-tasks --cluster "$cluster" --desired-status RUNNING --output json 2>&1)"; then
      fail "could not discover running ECS tasks for $cluster: $running_out"
    fi
    if ! pending_out="$(aws_cmd ecs list-tasks --cluster "$cluster" --desired-status PENDING --output json 2>&1)"; then
      fail "could not discover pending ECS tasks for $cluster: $pending_out"
    fi
    services="$(jq -c '.serviceArns // []' <<< "$service_out")"
    tasks="$(jq -cn --argjson running "$(jq -c '.taskArns // []' <<< "$running_out")" --argjson pending "$(jq -c '.taskArns // []' <<< "$pending_out")" '$running + $pending | unique')"
    while IFS= read -r service; do
      [ -n "$service" ] || continue
      discovered="$(jq -c --arg id "$service" --arg parent "$cluster" '. + [{resource_type:"ecs:service",id:$id,arn:$id,parent_id:$parent,sources:["ecs-discovery"],tag_entry:null,force_delete:false}]' <<< "$discovered")"
    done < <(jq -r '.[]' <<< "$services")
    while IFS= read -r task; do
      [ -n "$task" ] || continue
      discovered="$(jq -c --arg id "$task" --arg parent "$cluster" '. + [{resource_type:"ecs:task",id:$id,arn:$id,parent_id:$parent,sources:["ecs-discovery"],tag_entry:null,force_delete:false}]' <<< "$discovered")"
    done < <(jq -r '.[]' <<< "$tasks")
  done < <(jq -r '.[] | select(.resource_type == "ecs:cluster") | .id' <<< "$base_candidates")
  printf '%s\n' "$discovered"
}

collect_tag_inventory() {
  local start offset target delay out entries candidates observation
  local all_entries='[]' all_candidates='[]' observations='[]'
  start=$SECONDS
  for offset in $TAG_REQUERY_OFFSETS; do
    if ! [[ "$offset" =~ ^[0-9]+$ ]]; then
      fail "TAG_REQUERY_OFFSETS contains a non-integer value"
    fi
    target=$((start + offset))
    delay=$((target - SECONDS))
    [ "$delay" -le 0 ] || sleep "$delay"
    if out="$(aws_cmd resourcegroupstaggingapi get-resources --tag-filters "Key=env_id,Values=$ENV_ID" --output json 2>&1)"; then
      if ! entries="$(jq -c '.ResourceTagMappingList // []' <<< "$out")"; then
        entries='[]'
        observation="$(jq -cn --arg at "$(now_iso)" --arg error malformed-response '{observed_at:$at,status:"indeterminate",error:$error}')"
      else
        candidates="$(normalize_tag_entries "$entries")"
        printf '%s\n' "$candidates" > "$tmp_dir/tag-candidates-$offset.json"
        all_candidates="$(jq -c --argjson more "$candidates" '. + $more' <<< "$all_candidates")"
        all_entries="$(jq -c --argjson more "$entries" '. + $more | unique_by(.ResourceARN)' <<< "$all_entries")"
        observation="$(jq -cn --arg at "$(now_iso)" --argjson count "$(jq 'length' <<< "$entries")" '{observed_at:$at,status:"ok",count:$count}')"
      fi
    else
      observation="$(jq -cn --arg at "$(now_iso)" --arg error "$out" '{observed_at:$at,status:"indeterminate",error:$error}')"
    fi
    observations="$(jq -c --argjson observation "$observation" '. + [$observation]' <<< "$observations")"
  done
  printf '%s\n' "$all_entries" > "$tmp_dir/tag-entries.json"
  printf '%s\n' "$all_candidates" > "$tmp_dir/tag-candidates.json"
  printf '%s\n' "$observations" > "$tmp_dir/tag-observations.json"
}

echo "== close-env.sh: env_id=$ENV_ID target=$TARGET =="
current_status=""
existing_manifest='{}'
lease_get_err="$tmp_dir/lease-get.err"
set +e
lease_json="$("$LEASE_SH" get "$ENV_ID" 2>"$lease_get_err")"
lease_get_rc=$?
set -e
if [ "$lease_get_rc" -eq 0 ]; then
  current_status="$(jq -r '.status' <<< "$lease_json")"
  lease_generation="$(jq -r '.generation // empty' <<< "$lease_json")"
  if [ -n "$EXPECTED_GENERATION" ] && [ "$lease_generation" != "$EXPECTED_GENERATION" ]; then
    echo "close-env.sh: lease generation mismatch for $ENV_ID: expected $EXPECTED_GENERATION, current ${lease_generation:-missing}; refusing cleanup" >&2
    exit 3
  fi
  existing_manifest="$(jq -c '.manifest // {}' <<< "$lease_json")"
elif [ "$lease_get_rc" -eq 1 ] && grep -q 'no lease for' "$lease_get_err"; then
  current_status=""
else
  # A read error (network, throttling, IAM) must never look like "nothing to
  # close": exit non-zero without touching the lease.
  echo "close-env.sh: could not read the lease for $ENV_ID (rc=$lease_get_rc): $(cat "$lease_get_err")" >&2
  exit 2
fi
case "$current_status" in
  closed) echo "lease already closed; nothing to do"; exit 0 ;;
  open|closing|cleanup_failed) ;;
  "") echo "close-env.sh: no lease for $ENV_ID; nothing to close" >&2; exit 0 ;;
  *) echo "close-env.sh: unexpected lease status '$current_status'" >&2; exit 2 ;;
esac

claim_args=(begin-cleanup "$ENV_ID")
[ "$FORCE_RETRY" != true ] || claim_args+=(--force-retry)
"$LEASE_SH" "${claim_args[@]}" >/dev/null

if [ "$TARGET" = aws ]; then
  for variable in api_image redis_image clickhouse_image; do
    if ! image_ref="$(jq -er --arg variable "$variable" \
      '.images[$variable] | select(type == "string" and length > 0)' <<< "$existing_manifest")"; then
      fail "lease manifest lacks required AWS image reference: $variable"
    fi
    destroy_image_vars+=(-var "$variable=$image_ref")
  done
fi

tf_init || fail "terraform init failed"
# Both reads fail closed: a backend or lock error must not shrink the
# candidate set (an empty state is a successful read that lists nothing).
state_err="$tmp_dir/state-read.err"
set +e
state_list="$(tf_raw state list 2>"$state_err")"
state_list_rc=$?
set -e
if [ "$state_list_rc" -ne 0 ]; then
  if grep -q 'No state file was found' "$state_err"; then
    state_list=""
    resource_values_json='[]'
  else
    fail "terraform state list failed: $(cat "$state_err")"
  fi
else
  state_json="$(tf_raw show -json 2>"$state_err")" \
    || fail "terraform show -json failed: $(cat "$state_err")"
  resource_values_json="$(jq -c '[(.values.root_module? // {}) | recurse(.child_modules[]?) | .resources[]?]' <<< "$state_json")" \
    || fail "terraform show -json returned malformed JSON"
fi
state_candidates > "$tmp_dir/state-candidates.json"
legacy_manifest_candidates > "$tmp_dir/legacy-candidates.json"
printf '%s\n' "$(jq -c '.candidates // []' <<< "$existing_manifest")" > "$tmp_dir/prior-candidates.json"
prior_tag_entries="$(jq -c '.tagging_inventory // []' <<< "$existing_manifest")"
normalize_tag_entries "$prior_tag_entries" > "$tmp_dir/prior-tag-candidates.json"

if pre_tag_out="$(aws_cmd resourcegroupstaggingapi get-resources --tag-filters "Key=env_id,Values=$ENV_ID" --output json 2>&1)"; then
  pre_tag_entries="$(jq -c '.ResourceTagMappingList // []' <<< "$pre_tag_out")" \
    || fail "pre-destroy tag inventory returned malformed JSON"
  pre_tag_status=ok
else
  pre_tag_entries='[]'
  pre_tag_status=indeterminate
fi
normalize_tag_entries "$pre_tag_entries" > "$tmp_dir/pre-tag-candidates.json"

base_candidates="$(merge_candidate_files \
  "$tmp_dir/prior-candidates.json" \
  "$tmp_dir/legacy-candidates.json" \
  "$tmp_dir/prior-tag-candidates.json" \
  "$tmp_dir/state-candidates.json" \
  "$tmp_dir/pre-tag-candidates.json")"
discover_ecs_candidates "$base_candidates" > "$tmp_dir/ecs-candidates.json"
printf '%s\n' "$base_candidates" > "$tmp_dir/base-candidates.json"
candidates="$(merge_candidate_files "$tmp_dir/base-candidates.json" "$tmp_dir/ecs-candidates.json")"

manifest_json="$(jq -cn \
  --argjson old "$existing_manifest" \
  --arg env_id "$ENV_ID" \
  --arg target "$TARGET" \
  --arg pre_tag_status "$pre_tag_status" \
  --argjson candidates "$candidates" \
  --argjson pre_tag_entries "$pre_tag_entries" \
  --argjson state_resources "$(jq -R -s -c 'split("\n") | map(select(length > 0))' <<< "$state_list")" '
    def union($left; $right): (($left // []) + $right | unique);
    $old + {
      env_id: $env_id,
      target: $target,
      state_resources: union($old.state_resources; $state_resources),
      candidates: $candidates,
      task_definition_arns: [$candidates[] | select(.resource_type == "ecs:task-definition") | .id] | unique,
      tagging_inventory_status: $pre_tag_status,
      tagging_inventory: (($old.tagging_inventory // []) + $pre_tag_entries | unique_by(.ResourceARN)),
      stale_tag_entries: ($old.stale_tag_entries // {count:0,entries:[]}),
      allowances: ($old.allowances // []),
      verification_runs: ($old.verification_runs // [])
    }')" || fail "could not build cleanup manifest"
persist_manifest

while IFS=$'\t' read -r cluster service; do
  [ -n "$service" ] || continue
  # A retry after a successful destroy finds no service; only ACTIVE or
  # DRAINING services are scaled, anything else is already gone.
  svc_err="$tmp_dir/describe-service.err"
  if svc_status="$(aws_cmd ecs describe-services --cluster "$cluster" --services "$service" \
      --query 'services[0].status' --output text 2>"$svc_err")"; then
    :
  elif grep -qE 'ClusterNotFoundException|ServiceNotFoundException' "$svc_err"; then
    svc_status="MISSING"
  else
    fail "describe-services failed for $service: $(cat "$svc_err")"
  fi
  case "$svc_status" in
    ACTIVE|DRAINING)
      echo "scaling $service to 0"
      aws_cmd ecs update-service --cluster "$cluster" --service "$service" --desired-count 0 >/dev/null \
        || fail "failed to scale $service to 0"
      AWS_OUTER_TIMEOUT_SECONDS=660 \
        aws_cmd ecs wait services-stable --cluster "$cluster" --services "$service" \
        || fail "$service did not reach stable at 0"
      ;;
    MISSING|None|INACTIVE)
      echo "skip scaling $service: status=$svc_status (already gone)"
      ;;
    *)
      fail "unexpected service status '$svc_status' for $service"
      ;;
  esac
done < <(jq -r '.[] | select(.resource_type == "ecs:service" and ((.sources // []) | index("ecs-discovery"))) | [.parent_id,.id] | @tsv' <<< "$candidates")

destroy_ok=false
for attempt in 1 2 3; do
  echo "terraform destroy attempt $attempt/3"
  if tf_destroy; then
    destroy_ok=true
    break
  fi
done
[ "$destroy_ok" = true ] || fail "terraform destroy failed after 3 attempts"

while IFS= read -r arn; do
  [ -n "$arn" ] || continue
  status=ACTIVE
  for _ in $(seq 1 20); do
    if describe_out="$(aws_cmd ecs describe-task-definition --task-definition "$arn" --output json 2>&1)"; then
      status="$(jq -r '.taskDefinition.status // "UNKNOWN"' <<< "$describe_out")"
    elif grep -qiE 'ClientException.*not found|not found|does not exist' <<< "$describe_out"; then
      status=DELETED
    else
      fail "DescribeTaskDefinition failed for $arn: $describe_out"
    fi
    case "$status" in
      INACTIVE|DELETE_IN_PROGRESS|DELETED) break ;;
      ACTIVE) sleep 3 ;;
      *) fail "unexpected task-definition status '$status' for $arn" ;;
    esac
  done
  [ "$status" != ACTIVE ] || fail "task definition did not become INACTIVE: $arn"
  if [ "$status" = INACTIVE ]; then
    delete_stdout="$tmp_dir/delete.stdout"
    delete_stderr="$tmp_dir/delete.stderr"
    set +e
    aws_cmd ecs delete-task-definitions --task-definitions "$arn" >"$delete_stdout" 2>"$delete_stderr"
    delete_rc=$?
    set -e
    delete_response_valid=false
    delete_requested_failure=false
    if jq -e 'type == "object" and (.failures | type == "array")' "$delete_stdout" >/dev/null 2>&1; then
      delete_response_valid=true
      if jq -e --arg arn "$arn" 'any(.failures[]; .arn == $arn)' "$delete_stdout" >/dev/null; then
        delete_requested_failure=true
      fi
    fi
    if [ "$delete_rc" -eq 0 ] && [ "$delete_response_valid" = true ] && \
       [ "$delete_requested_failure" = false ]; then
      echo "requested task-definition deletion: $arn"
    else
      allowance_fixture="$tmp_dir/delete-allowance.json"
      jq -n \
        --arg arn "$arn" \
        --arg status "$status" \
        --argjson rc "$delete_rc" \
        --rawfile stdout "$delete_stdout" \
        --rawfile stderr "$delete_stderr" \
        '{arn:$arn,status:$status,response:{rc:$rc,stdout:$stdout,stderr:$stderr}}' > "$allowance_fixture"
      if allowance="$("$CLEANUP_VERIFIER_SH" task-definition-delete-allowance "$TARGET" "$allowance_fixture")"; then
        manifest_json="$(jq -c --argjson allowance "$(jq -c '.allowance' <<< "$allowance")" '
          .allowances = ((.allowances // []) + [$allowance] | unique_by([.id,.arn]))' <<< "$manifest_json")"
        persist_manifest
      else
        if [ "$delete_requested_failure" = true ]; then
          fail "DeleteTaskDefinitions reported a failure for the requested ARN: $arn"
        elif [ "$delete_response_valid" != true ]; then
          fail "DeleteTaskDefinitions returned malformed JSON for $arn"
        else
          fail "DeleteTaskDefinitions failed for $arn: $(cat "$delete_stderr")"
        fi
      fi
    fi
  fi
done < <(jq -r '.task_definition_arns[]?' <<< "$manifest_json")

collect_tag_inventory
discovery_candidates='[]'
if ! jq -e 'length > 0 and all(.[]; .status == "ok")' \
  "$tmp_dir/tag-observations.json" >/dev/null; then
  discovery_candidates='[{"resource_type":"unsupported","id":"tag-inventory-incomplete","arn":null,"parent_id":null,"sources":["tag-discovery"],"tag_entry":null,"force_delete":false}]'
fi
printf '%s\n' "$candidates" > "$tmp_dir/pre-final-candidates.json"
printf '%s\n' "$discovery_candidates" > "$tmp_dir/discovery-candidates.json"
candidates="$(merge_candidate_files \
  "$tmp_dir/pre-final-candidates.json" \
  "$tmp_dir/tag-candidates.json" \
  "$tmp_dir/discovery-candidates.json")"
manifest_json="$(jq -c \
  --argjson candidates "$candidates" \
  --argjson entries "$(cat "$tmp_dir/tag-entries.json")" \
  --argjson observations "$(cat "$tmp_dir/tag-observations.json")" '
    .candidates = $candidates
    | .tagging_inventory = ((.tagging_inventory // []) + $entries | unique_by(.ResourceARN))
    | .tag_inventory_observations = ((.tag_inventory_observations // []) + $observations)
    | .tagging_inventory_status = (
        if ($observations | length) > 0 and all($observations[]; .status == "ok")
        then "ok"
        else "indeterminate"
        end
      )' <<< "$manifest_json")"
persist_manifest

printf '%s\n' "$candidates" > "$tmp_dir/final-candidates.json"
verification_start="$(now_epoch)"
verification_deadline=$((verification_start + CLEANUP_VERIFY_DEADLINE_SECONDS))
backoff_index=0
read -r -a verification_backoff <<< "$CLEANUP_VERIFY_BACKOFF"
while :; do
  verification="$("$CLEANUP_VERIFIER_SH" verify-live "$tmp_dir/final-candidates.json")"
  run="$(jq -c --arg started_at "$(date -u -r "$verification_start" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$verification_start" +%Y-%m-%dT%H:%M:%SZ)" --arg completed_at "$(now_iso)" '
    {started_at:$started_at,completed_at:$completed_at,results:.results,summary:.summary}' <<< "$verification")"
  stale_entries="$(jq -c '.stale_tag_entries' <<< "$verification")"
  manifest_json="$(jq -c --argjson run "$run" --argjson stale "$stale_entries" '
    ((.stale_tag_entries.entries // []) + $stale | unique_by(.ResourceARN)) as $entries
    | .stale_tag_entries = {count:($entries|length),entries:$entries}
    | .verification_runs = ((.verification_runs // []) + [$run])' <<< "$manifest_json")"
  persist_manifest

  live_count="$(jq -r '.summary.live' <<< "$verification")"
  pending_count="$(jq -r '.summary.pending' <<< "$verification")"
  indeterminate_count="$(jq -r '.summary.indeterminate' <<< "$verification")"
  if [ "$live_count" -eq 0 ] && [ "$pending_count" -eq 0 ] && [ "$indeterminate_count" -eq 0 ]; then
    break
  fi
  if [ "$(now_epoch)" -ge "$verification_deadline" ]; then
    if [ "$live_count" -gt 0 ] || [ "$indeterminate_count" -gt 0 ]; then
      fail "cleanup verification deadline reached: live=$live_count indeterminate=$indeterminate_count pending=$pending_count"
    fi
    echo "close-env.sh: verification deadline reached with pending=$pending_count deletion transitions still in progress; stage 2 (sweeper) re-verifies them"
    break
  fi
  sleep_seconds="${verification_backoff[$backoff_index]:-30}"
  [ "$sleep_seconds" -le 30 ] || sleep_seconds=30
  remaining=$((verification_deadline - $(now_epoch)))
  [ "$sleep_seconds" -le "$remaining" ] || sleep_seconds="$remaining"
  [ "$sleep_seconds" -le 0 ] || sleep "$sleep_seconds"
  backoff_index=$((backoff_index + 1))
done

echo "close-env.sh: $ENV_ID stage 1 complete; lease remains 'closing' for the sweeper"
