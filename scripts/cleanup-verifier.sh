#!/usr/bin/env bash
# Typed, exact-resource cleanup predicates. Recorded responses and live probes
# share the same classifier so offline tests exercise production semantics.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AWS_CLI_SH="${AWS_CLI_SH:-$SCRIPT_DIR/aws-cli.sh}"

usage() {
  cat <<'EOF'
Usage:
  cleanup-verifier.sh normalize-tags
  cleanup-verifier.sh merge-candidates <json-file>...
  cleanup-verifier.sh classify <candidate-json-file> <response-json-file>
  cleanup-verifier.sh verify-recorded <fixture-json-file>
  cleanup-verifier.sh verify-live <candidates-json-file>
  cleanup-verifier.sh task-definition-delete-allowance <aws|localstack> <fixture-json-file>
EOF
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

emit_candidate() {
  local resource_type="$1"
  local id="$2"
  local arn="$3"
  local parent_id="${4:-}"
  local tag_entry="${5:-null}"
  local force_delete="${6:-false}"
  jq -cn \
    --arg resource_type "$resource_type" \
    --arg id "$id" \
    --arg arn "$arn" \
    --arg parent_id "$parent_id" \
    --argjson tag_entry "$tag_entry" \
    --argjson force_delete "$force_delete" '
      {
        resource_type: $resource_type,
        id: $id,
        arn: (if $arn == "" then null else $arn end),
        parent_id: (if $parent_id == "" then null else $parent_id end),
        sources: ["tag"],
        tag_entry: $tag_entry,
        force_delete: $force_delete
      }'
}

candidate_from_arn() {
  local arn="$1"
  local tag_entry="${2:-null}"
  local prefix _partition service _region _authority resource
  IFS=: read -r prefix _partition service _region _authority resource <<< "$arn"
  if [ "$prefix" != "arn" ] || [ -z "$service" ] || [ -z "$resource" ]; then
    emit_candidate unsupported "$arn" "$arn" "" "$tag_entry"
    return
  fi

  local kind id parent tail name
  case "$service" in
    ec2)
      kind="${resource%%/*}"
      id="${resource#*/}"
      case "$kind" in
        vpc|subnet|security-group|security-group-rule|internet-gateway|route-table|vpc-endpoint)
          emit_candidate "ec2:$kind" "$id" "$arn" "" "$tag_entry"
          ;;
        *) emit_candidate unsupported "$arn" "$arn" "" "$tag_entry" ;;
      esac
      ;;
    elasticloadbalancing)
      kind="${resource%%/*}"
      case "$kind" in
        loadbalancer|targetgroup|listener|listener-rule)
          case "$kind" in
            loadbalancer) kind=load-balancer ;;
            targetgroup) kind='target-group' ;;
          esac
          emit_candidate "elbv2:$kind" "$arn" "$arn" "" "$tag_entry"
          ;;
        *) emit_candidate unsupported "$arn" "$arn" "" "$tag_entry" ;;
      esac
      ;;
    ecs)
      kind="${resource%%/*}"
      tail="${resource#*/}"
      case "$kind" in
        cluster|task-definition)
          emit_candidate "ecs:$kind" "$arn" "$arn" "" "$tag_entry"
          ;;
        service|task)
          if [ "$tail" = "${tail#*/}" ]; then
            emit_candidate unsupported "$arn" "$arn" "" "$tag_entry"
          else
            parent="${tail%%/*}"
            emit_candidate "ecs:$kind" "$arn" "$arn" "$parent" "$tag_entry"
          fi
          ;;
        *) emit_candidate unsupported "$arn" "$arn" "" "$tag_entry" ;;
      esac
      ;;
    servicediscovery)
      kind="${resource%%/*}"
      id="${resource#*/}"
      case "$kind" in
        namespace|service) emit_candidate "servicediscovery:$kind" "$id" "$arn" "" "$tag_entry" ;;
        *) emit_candidate unsupported "$arn" "$arn" "" "$tag_entry" ;;
      esac
      ;;
    logs)
      case "$resource" in
        log-group:*)
          name="${resource#log-group:}"
          name="${name%:*}"
          emit_candidate logs:log-group "$name" "$arn" "" "$tag_entry"
          ;;
        *) emit_candidate unsupported "$arn" "$arn" "" "$tag_entry" ;;
      esac
      ;;
    secretsmanager)
      case "$resource" in
        secret:*) emit_candidate secretsmanager:secret "$arn" "$arn" "" "$tag_entry" ;;
        *) emit_candidate unsupported "$arn" "$arn" "" "$tag_entry" ;;
      esac
      ;;
    s3)
      emit_candidate s3:bucket "$resource" "$arn" "" "$tag_entry"
      ;;
    sns)
      emit_candidate sns:topic "$arn" "$arn" "" "$tag_entry"
      ;;
    cloudwatch)
      case "$resource" in
        alarm:*) emit_candidate cloudwatch:alarm "${resource#alarm:}" "$arn" "" "$tag_entry" ;;
        *) emit_candidate unsupported "$arn" "$arn" "" "$tag_entry" ;;
      esac
      ;;
    iam)
      case "$resource" in
        role/*) emit_candidate iam:role "${resource##*/}" "$arn" "" "$tag_entry" ;;
        *) emit_candidate unsupported "$arn" "$arn" "" "$tag_entry" ;;
      esac
      ;;
    *)
      emit_candidate unsupported "$arn" "$arn" "" "$tag_entry"
      ;;
  esac
}

normalize_tags() {
  local entries
  entries="$(cat)"
  if ! jq -e 'type == "array" and all(.[]; (.ResourceARN | type) == "string")' <<< "$entries" >/dev/null; then
    echo "cleanup-verifier.sh: stdin must be a tagging-api entry array" >&2
    exit 2
  fi
  local candidates='[]' entry arn candidate
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    arn="$(jq -r '.ResourceARN' <<< "$entry")"
    candidate="$(candidate_from_arn "$arn" "$entry")"
    candidates="$(jq -c --argjson candidate "$candidate" '. + [$candidate]' <<< "$candidates")"
  done < <(jq -c '.[]' <<< "$entries")
  printf '%s\n' "$candidates"
}

merge_candidates() {
  local combined='[]' file
  for file in "$@"; do
    if ! jq -e 'type == "array"' "$file" >/dev/null; then
      echo "cleanup-verifier.sh: candidate file is not an array: $file" >&2
      exit 2
    fi
    combined="$(jq -c --argjson more "$(cat "$file")" '. + $more' <<< "$combined")"
  done
  jq -c '
    sort_by(.resource_type, .id)
    | group_by([.resource_type, .id])
    | map(
        reduce .[] as $item (
          {resource_type: .[0].resource_type, id: .[0].id, arn: null, parent_id: null, sources: [], tag_entry: null, force_delete: false};
          .arn = (.arn // $item.arn // null)
          | .parent_id = (.parent_id // $item.parent_id // null)
          | .sources = ((.sources + ($item.sources // [])) | unique)
          | .tag_entry = (.tag_entry // $item.tag_entry // null)
          | .force_delete = (.force_delete or ($item.force_delete // false))
        )
      )' <<< "$combined"
}

emit_result() {
  local candidate="$1"
  local outcome="$2"
  local reason="$3"
  local observed_state="${4:-}"
  jq -cn \
    --argjson candidate "$candidate" \
    --arg outcome "$outcome" \
    --arg reason "$reason" \
    --arg observed_state "$observed_state" \
    --arg observed_at "$(now_iso)" '
      $candidate + {
        outcome: $outcome,
        reason: $reason,
        observed_state: (if $observed_state == "" then null else $observed_state end),
        observed_at: $observed_at
      }'
}

not_found_for_type() {
  local resource_type="$1"
  local stderr="$2"
  case "$resource_type" in
    ec2:*) grep -qiE 'Invalid[^[:space:]]*\.NotFound|NotFound|not found|does not exist|404' <<< "$stderr" ;;
    elbv2:*) grep -qiE 'LoadBalancerNotFound|TargetGroupNotFound|ListenerNotFound|RuleNotFound|not found|does not exist' <<< "$stderr" ;;
    ecs:*) grep -qiE 'ClusterNotFound|ServiceNotFound|ClientException.*not found|not found|does not exist' <<< "$stderr" ;;
    servicediscovery:*) grep -qiE 'NamespaceNotFound|ServiceNotFound|ResourceNotFound|not found' <<< "$stderr" ;;
    logs:log-group|secretsmanager:secret) grep -qiE 'ResourceNotFound|not found' <<< "$stderr" ;;
    s3:bucket) grep -qiE 'NoSuchBucket|Not Found|404' <<< "$stderr" ;;
    sns:topic) grep -qiE 'NotFound|not found' <<< "$stderr" ;;
    iam:role) grep -qiE 'NoSuchEntity|not found' <<< "$stderr" ;;
    *) return 1 ;;
  esac
}

classify() {
  local candidate_file="$1"
  local response_file="$2"
  local candidate response resource_type id rc stderr output_json force_delete
  candidate="$(cat "$candidate_file")"
  response="$(cat "$response_file")"
  if ! jq -e 'type == "object" and (.resource_type | type) == "string" and (.id | type) == "string"' <<< "$candidate" >/dev/null || \
     ! jq -e 'type == "object" and (.rc | type) == "number" and has("stdout") and (.stderr | type) == "string"' <<< "$response" >/dev/null; then
    echo "cleanup-verifier.sh: malformed candidate or response" >&2
    exit 2
  fi

  resource_type="$(jq -r '.resource_type' <<< "$candidate")"
  id="$(jq -r '.id' <<< "$candidate")"
  rc="$(jq -r '.rc' <<< "$response")"
  stderr="$(jq -r '.stderr' <<< "$response")"
  force_delete="$(jq -r '.force_delete // false' <<< "$candidate")"

  case "$resource_type" in
    ec2:vpc|ec2:subnet|ec2:security-group|ec2:security-group-rule|ec2:internet-gateway|ec2:route-table|ec2:vpc-endpoint|elbv2:load-balancer|elbv2:target-group|elbv2:listener|elbv2:listener-rule|ecs:cluster|ecs:service|ecs:task|ecs:task-definition|servicediscovery:namespace|servicediscovery:service|logs:log-group|secretsmanager:secret|s3:bucket|sns:topic|cloudwatch:alarm|iam:role) ;;
    *) emit_result "$candidate" indeterminate unsupported-resource-type; return ;;
  esac

  if [ "$rc" -eq 124 ]; then
    emit_result "$candidate" indeterminate aws-timeout
    return
  fi
  if [ "$rc" -ne 0 ]; then
    if not_found_for_type "$resource_type" "$stderr"; then
      emit_result "$candidate" gone exact-api-not-found
    else
      emit_result "$candidate" indeterminate aws-error
    fi
    return
  fi

  case "$resource_type" in
    s3:bucket)
      emit_result "$candidate" live head-bucket-succeeded
      return
      ;;
  esac

  output_json="$(jq -c '.stdout | if type == "string" then (fromjson? // null) else . end' <<< "$response")"
  if [ "$output_json" = "null" ] || ! jq -e 'type == "object"' <<< "$output_json" >/dev/null; then
    emit_result "$candidate" indeterminate malformed-response
    return
  fi

  local valid match state ecs_failure
  ecs_failure=""
  valid=false
  match=false
  state=""
  case "$resource_type" in
    ec2:vpc)
      valid="$(jq -r 'has("Vpcs") and (.Vpcs | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.Vpcs[]?; .VpcId == $id)' <<< "$output_json")"
      ;;
    ec2:subnet)
      valid="$(jq -r 'has("Subnets") and (.Subnets | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.Subnets[]?; .SubnetId == $id)' <<< "$output_json")"
      ;;
    ec2:security-group)
      valid="$(jq -r 'has("SecurityGroups") and (.SecurityGroups | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.SecurityGroups[]?; .GroupId == $id)' <<< "$output_json")"
      ;;
    ec2:security-group-rule)
      valid="$(jq -r 'has("SecurityGroupRules") and (.SecurityGroupRules | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.SecurityGroupRules[]?; .SecurityGroupRuleId == $id)' <<< "$output_json")"
      ;;
    ec2:internet-gateway)
      valid="$(jq -r 'has("InternetGateways") and (.InternetGateways | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.InternetGateways[]?; .InternetGatewayId == $id)' <<< "$output_json")"
      ;;
    ec2:route-table)
      valid="$(jq -r 'has("RouteTables") and (.RouteTables | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.RouteTables[]?; .RouteTableId == $id)' <<< "$output_json")"
      ;;
    ec2:vpc-endpoint)
      valid="$(jq -r 'has("VpcEndpoints") and (.VpcEndpoints | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.VpcEndpoints[]?; .VpcEndpointId == $id)' <<< "$output_json")"
      if [ "$match" = true ]; then
        state="$(jq -r --arg id "$id" '.VpcEndpoints[] | select(.VpcEndpointId == $id) | .State // empty' <<< "$output_json" | head -n1)"
      fi
      ;;
    elbv2:load-balancer)
      valid="$(jq -r 'has("LoadBalancers") and (.LoadBalancers | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.LoadBalancers[]?; .LoadBalancerArn == $id)' <<< "$output_json")"
      ;;
    elbv2:target-group)
      valid="$(jq -r 'has("TargetGroups") and (.TargetGroups | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.TargetGroups[]?; .TargetGroupArn == $id)' <<< "$output_json")"
      ;;
    elbv2:listener)
      valid="$(jq -r 'has("Listeners") and (.Listeners | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.Listeners[]?; .ListenerArn == $id)' <<< "$output_json")"
      ;;
    elbv2:listener-rule)
      valid="$(jq -r 'has("Rules") and (.Rules | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.Rules[]?; .RuleArn == $id)' <<< "$output_json")"
      ;;
    ecs:cluster)
      valid="$(jq -r 'has("clusters") and (.clusters | type == "array") and has("failures") and (.failures | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.clusters[]?; .clusterArn == $id)' <<< "$output_json")"
      if [ "$valid" = true ]; then
        ecs_failure="$(jq -r --arg id "$id" '
          if (.failures | length) == 0 then "none"
          elif all(.failures[];
            try (.arn == $id and .reason == "MISSING") catch false)
          then "exact-missing" else "indeterminate" end' <<< "$output_json")"
      fi
      if [ "$match" = true ]; then state="$(jq -r --arg id "$id" '.clusters[] | select(.clusterArn == $id) | .status // empty' <<< "$output_json" | head -n1)"; fi
      ;;
    ecs:service)
      valid="$(jq -r 'has("services") and (.services | type == "array") and has("failures") and (.failures | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.services[]?; .serviceArn == $id)' <<< "$output_json")"
      if [ "$valid" = true ]; then
        ecs_failure="$(jq -r --arg id "$id" '
          if (.failures | length) == 0 then "none"
          elif all(.failures[];
            try (.arn == $id and .reason == "MISSING") catch false)
          then "exact-missing" else "indeterminate" end' <<< "$output_json")"
      fi
      if [ "$match" = true ]; then state="$(jq -r --arg id "$id" '.services[] | select(.serviceArn == $id) | .status // empty' <<< "$output_json" | head -n1)"; fi
      ;;
    ecs:task)
      valid="$(jq -r 'has("tasks") and (.tasks | type == "array") and has("failures") and (.failures | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.tasks[]?; .taskArn == $id)' <<< "$output_json")"
      if [ "$valid" = true ]; then
        ecs_failure="$(jq -r --arg id "$id" '
          if (.failures | length) == 0 then "none"
          elif all(.failures[];
            try (.arn == $id and .reason == "MISSING") catch false)
          then "exact-missing" else "indeterminate" end' <<< "$output_json")"
      fi
      if [ "$match" = true ]; then state="$(jq -r --arg id "$id" '.tasks[] | select(.taskArn == $id) | .lastStatus // empty' <<< "$output_json" | head -n1)"; fi
      ;;
    ecs:task-definition)
      valid="$(jq -r 'has("taskDefinition") and (.taskDefinition | type == "object")' <<< "$output_json")"
      match="$valid"
      state="$(jq -r '.taskDefinition.status // empty' <<< "$output_json")"
      ;;
    servicediscovery:namespace)
      valid="$(jq -r 'has("Namespace") and (.Namespace | type == "object")' <<< "$output_json")"
      match="$valid"
      ;;
    servicediscovery:service)
      valid="$(jq -r 'has("Service") and (.Service | type == "object")' <<< "$output_json")"
      match="$valid"
      ;;
    logs:log-group)
      valid="$(jq -r 'has("logGroups") and (.logGroups | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.logGroups[]?; .logGroupName == $id)' <<< "$output_json")"
      ;;
    secretsmanager:secret)
      valid="$(jq -r 'has("ARN") and (.ARN | type == "string")' <<< "$output_json")"
      match="$valid"
      if jq -e 'has("DeletedDate") and .DeletedDate != null' <<< "$output_json" >/dev/null; then state=DeletedDate; fi
      ;;
    sns:topic)
      valid="$(jq -r 'has("Attributes") and (.Attributes | type == "object")' <<< "$output_json")"
      match="$valid"
      ;;
    cloudwatch:alarm)
      valid="$(jq -r 'has("MetricAlarms") and (.MetricAlarms | type == "array")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" 'any(.MetricAlarms[]?; .AlarmName == $id)' <<< "$output_json")"
      ;;
    iam:role)
      valid="$(jq -r 'has("Role") and (.Role | type == "object")' <<< "$output_json")"
      match="$(jq -r --arg id "$id" '.Role.RoleName == $id' <<< "$output_json")"
      ;;
  esac

  if [ "$valid" != true ]; then
    emit_result "$candidate" indeterminate malformed-response
    return
  fi
  case "$resource_type" in
    ecs:cluster|ecs:service|ecs:task)
      if [ "$ecs_failure" = indeterminate ] || { [ "$ecs_failure" = exact-missing ] && [ "$match" = true ]; }; then
        emit_result "$candidate" indeterminate ecs-failure-indeterminate
        return
      fi
      if [ "$match" != true ]; then
        if [ "$ecs_failure" = exact-missing ]; then
          emit_result "$candidate" gone exact-ecs-missing-failure
        else
          emit_result "$candidate" indeterminate ecs-absence-unconfirmed
        fi
        return
      fi
      ;;
    *)
      if [ "$match" != true ]; then
        emit_result "$candidate" gone exact-resource-missing
        return
      fi
      ;;
  esac

  case "$resource_type:$state" in
    ec2:vpc-endpoint:deleted) emit_result "$candidate" gone terminal-state "$state" ;;
    ec2:vpc-endpoint:deleting) emit_result "$candidate" pending deletion-transition "$state" ;;
    ec2:vpc-endpoint:) emit_result "$candidate" indeterminate malformed-response ;;
    ecs:cluster:INACTIVE|ecs:service:INACTIVE|ecs:task:STOPPED|ecs:task-definition:INACTIVE|ecs:task-definition:DELETE_IN_PROGRESS)
      emit_result "$candidate" gone terminal-state "$state"
      ;;
    ecs:cluster:|ecs:service:|ecs:task:|ecs:task-definition:)
      emit_result "$candidate" indeterminate malformed-response
      ;;
    secretsmanager:secret:DeletedDate)
      if [ "$force_delete" = true ]; then
        emit_result "$candidate" gone force-delete-recorded "$state"
      else
        emit_result "$candidate" pending scheduled-deletion "$state"
      fi
      ;;
    *) emit_result "$candidate" live exact-resource-present "$state" ;;
  esac
}

summarize_results() {
  local results="$1"
  jq -cn --argjson results "$results" '
    def count($name): [$results[] | select(.outcome == $name)] | length;
    {
      results: $results,
      summary: {
        gone: count("gone"),
        pending: count("pending"),
        live: count("live"),
        indeterminate: count("indeterminate")
      },
      gone: [$results[] | select(.outcome == "gone")],
      pending: [$results[] | select(.outcome == "pending")],
      live: [$results[] | select(.outcome == "live")],
      indeterminate: [$results[] | select(.outcome == "indeterminate")],
      stale_tag_entries: [
        $results[]
        | select(.outcome == "gone" and ((.sources // []) | index("tag")))
        | (.tag_entry // {ResourceARN: .arn, Tags: []})
      ],
      passed: (count("live") == 0 and count("indeterminate") == 0)
    }'
}

verify_records() {
  local records="$1"
  local results='[]' record candidate response candidate_file response_file result
  while IFS= read -r record; do
    [ -n "$record" ] || continue
    candidate="$(jq -c '.candidate' <<< "$record")"
    response="$(jq -c '.response' <<< "$record")"
    candidate_file="$(mktemp)"
    response_file="$(mktemp)"
    printf '%s\n' "$candidate" > "$candidate_file"
    printf '%s\n' "$response" > "$response_file"
    result="$(classify "$candidate_file" "$response_file")"
    rm -f "$candidate_file" "$response_file"
    results="$(jq -c --argjson result "$result" '. + [$result]' <<< "$results")"
  done < <(jq -c '.[]' <<< "$records")
  summarize_results "$results"
}

verify_recorded() {
  local fixture_file="$1"
  local fixture records candidates entry candidate arn response
  fixture="$(cat "$fixture_file")"
  if ! jq -e 'type == "object"' <<< "$fixture" >/dev/null; then
    echo "cleanup-verifier.sh: recorded fixture must be an object" >&2
    exit 2
  fi
  records="$(jq -c '.records // []' <<< "$fixture")"
  if jq -e '.tag_response.ResourceTagMappingList | type == "array"' <<< "$fixture" >/dev/null; then
    candidates="$(jq -c '.tag_response.ResourceTagMappingList' <<< "$fixture" | normalize_tags)"
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      arn="$(jq -r '.arn' <<< "$candidate")"
      response="$(jq -c --arg arn "$arn" '.responses[$arn] // .default_response' <<< "$fixture")"
      records="$(jq -c --argjson candidate "$candidate" --argjson response "$response" '. + [{candidate: $candidate, response: $response}]' <<< "$records")"
    done < <(jq -c '.[]' <<< "$candidates")
  fi
  verify_records "$records"
}

probe_candidate() {
  local candidate="$1"
  local resource_type id parent_id candidate_file response_file out_file err_file rc response
  resource_type="$(jq -r '.resource_type' <<< "$candidate")"
  id="$(jq -r '.id' <<< "$candidate")"
  parent_id="$(jq -r '.parent_id // empty' <<< "$candidate")"
  out_file="$(mktemp)"
  err_file="$(mktemp)"
  set +e
  case "$resource_type" in
    ec2:vpc) "$AWS_CLI_SH" ec2 describe-vpcs --vpc-ids "$id" --output json >"$out_file" 2>"$err_file" ;;
    ec2:subnet) "$AWS_CLI_SH" ec2 describe-subnets --subnet-ids "$id" --output json >"$out_file" 2>"$err_file" ;;
    ec2:security-group) "$AWS_CLI_SH" ec2 describe-security-groups --group-ids "$id" --output json >"$out_file" 2>"$err_file" ;;
    ec2:security-group-rule) "$AWS_CLI_SH" ec2 describe-security-group-rules --security-group-rule-ids "$id" --output json >"$out_file" 2>"$err_file" ;;
    ec2:internet-gateway) "$AWS_CLI_SH" ec2 describe-internet-gateways --internet-gateway-ids "$id" --output json >"$out_file" 2>"$err_file" ;;
    ec2:route-table) "$AWS_CLI_SH" ec2 describe-route-tables --route-table-ids "$id" --output json >"$out_file" 2>"$err_file" ;;
    ec2:vpc-endpoint) "$AWS_CLI_SH" ec2 describe-vpc-endpoints --vpc-endpoint-ids "$id" --output json >"$out_file" 2>"$err_file" ;;
    elbv2:load-balancer) "$AWS_CLI_SH" elbv2 describe-load-balancers --load-balancer-arns "$id" --output json >"$out_file" 2>"$err_file" ;;
    elbv2:target-group) "$AWS_CLI_SH" elbv2 describe-target-groups --target-group-arns "$id" --output json >"$out_file" 2>"$err_file" ;;
    elbv2:listener) "$AWS_CLI_SH" elbv2 describe-listeners --listener-arns "$id" --output json >"$out_file" 2>"$err_file" ;;
    elbv2:listener-rule) "$AWS_CLI_SH" elbv2 describe-rules --rule-arns "$id" --output json >"$out_file" 2>"$err_file" ;;
    ecs:cluster) "$AWS_CLI_SH" ecs describe-clusters --clusters "$id" --output json >"$out_file" 2>"$err_file" ;;
    ecs:service) "$AWS_CLI_SH" ecs describe-services --cluster "$parent_id" --services "$id" --output json >"$out_file" 2>"$err_file" ;;
    ecs:task) "$AWS_CLI_SH" ecs describe-tasks --cluster "$parent_id" --tasks "$id" --output json >"$out_file" 2>"$err_file" ;;
    ecs:task-definition) "$AWS_CLI_SH" ecs describe-task-definition --task-definition "$id" --output json >"$out_file" 2>"$err_file" ;;
    servicediscovery:namespace) "$AWS_CLI_SH" servicediscovery get-namespace --id "$id" --output json >"$out_file" 2>"$err_file" ;;
    servicediscovery:service) "$AWS_CLI_SH" servicediscovery get-service --id "$id" --output json >"$out_file" 2>"$err_file" ;;
    logs:log-group) "$AWS_CLI_SH" logs describe-log-groups --log-group-name-prefix "$id" --output json >"$out_file" 2>"$err_file" ;;
    secretsmanager:secret) "$AWS_CLI_SH" secretsmanager describe-secret --secret-id "$id" --output json >"$out_file" 2>"$err_file" ;;
    s3:bucket) "$AWS_CLI_SH" s3api head-bucket --bucket "$id" >"$out_file" 2>"$err_file" ;;
    sns:topic) "$AWS_CLI_SH" sns get-topic-attributes --topic-arn "$id" --output json >"$out_file" 2>"$err_file" ;;
    cloudwatch:alarm) "$AWS_CLI_SH" cloudwatch describe-alarms --alarm-names "$id" --output json >"$out_file" 2>"$err_file" ;;
    iam:role) "$AWS_CLI_SH" iam get-role --role-name "$id" --output json >"$out_file" 2>"$err_file" ;;
    *) printf 'unsupported resource type: %s\n' "$resource_type" >"$err_file"; rc=2 ;;
  esac
  rc="${rc:-$?}"
  set -e
  response="$(jq -n --argjson rc "$rc" --rawfile stdout "$out_file" --rawfile stderr "$err_file" '{rc:$rc,stdout:$stdout,stderr:$stderr}')"
  candidate_file="$(mktemp)"
  response_file="$(mktemp)"
  printf '%s\n' "$candidate" > "$candidate_file"
  printf '%s\n' "$response" > "$response_file"
  classify "$candidate_file" "$response_file"
  rm -f "$candidate_file" "$response_file" "$out_file" "$err_file"
}

verify_live() {
  local candidates_file="$1"
  local candidates results='[]' candidate result
  candidates="$(cat "$candidates_file")"
  if ! jq -e 'type == "array"' <<< "$candidates" >/dev/null; then
    echo "cleanup-verifier.sh: candidates file must contain an array" >&2
    exit 2
  fi
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    result="$(probe_candidate "$candidate")"
    results="$(jq -c --argjson result "$result" '. + [$result]' <<< "$results")"
  done < <(jq -c '.[]' <<< "$candidates")
  summarize_results "$results"
}

task_definition_delete_allowance() {
  local target="$1"
  local fixture_file="$2"
  local fixture status arn rc stderr code
  fixture="$(cat "$fixture_file")"
  status="$(jq -r '.status // empty' <<< "$fixture")"
  arn="$(jq -r '.arn // empty' <<< "$fixture")"
  rc="$(jq -r '.response.rc // 0' <<< "$fixture")"
  stderr="$(jq -r '.response.stderr // ""' <<< "$fixture")"
  code="$(sed -n 's/.*(\([^)]*\)).*/\1/p' <<< "$stderr" | head -n1)"
  # LocalStack reports the unsupported operation as NotImplementedException in
  # some versions and InternalFailure in others (recorded 2026-09-02 from
  # LocalStack 2026.8.1); the message signature is the stable part, so the
  # error code is recorded but not matched.
  if [ "$target" = localstack ] && [ "$status" = INACTIVE ] && [ "$rc" -ne 0 ] && \
     [ -n "$code" ] && \
     grep -Fq 'DeleteTaskDefinitions' <<< "$stderr" && \
     grep -Fq 'is not currently supported by LocalStack' <<< "$stderr"; then
    jq -cn \
      --arg arn "$arn" \
      --arg error_code "$code" \
      --arg recorded_at "$(now_iso)" '
        {
          allowed: true,
          allowance: {
            id: "localstack-delete-task-definitions-inactive",
            arn: $arn,
            error_code: $error_code,
            recorded_at: $recorded_at
          }
        }'
    return 0
  fi
  jq -cn --arg target "$target" '{allowed:false,target:$target}'
  return 1
}

main() {
  local command="${1:-}"
  case "$command" in
    normalize-tags) shift; normalize_tags "$@" ;;
    merge-candidates) shift; merge_candidates "$@" ;;
    classify) shift; [ "$#" -eq 2 ] || { usage >&2; exit 2; }; classify "$@" ;;
    verify-recorded) shift; [ "$#" -eq 1 ] || { usage >&2; exit 2; }; verify_recorded "$@" ;;
    verify-live) shift; [ "$#" -eq 1 ] || { usage >&2; exit 2; }; verify_live "$@" ;;
    task-definition-delete-allowance) shift; [ "$#" -eq 2 ] || { usage >&2; exit 2; }; task_definition_delete_allowance "$@" ;;
    --help|-h) usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
