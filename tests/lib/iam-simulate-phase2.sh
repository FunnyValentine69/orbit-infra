#!/usr/bin/env bash
# shellcheck disable=SC2154 # Globals are provided by the sourcing contract suite.

# Phase-2 IAM simulator contracts. This file is sourced by
# tests/iam-simulate-contracts.sh so it shares that suite's result counters and
# temporary directory.

IAM_SIM_RUNNER="$REPO_ROOT/scripts/iam-simulate.sh"
IAM_SIM_ROLE_LANE="$REPO_ROOT/scripts/iam-simulate-roles.sh"
IAM_SIM_AWS_WRAPPER="$REPO_ROOT/scripts/aws-cli.sh"

phase2_setup() {
  phase2_dir="$tmp_dir/phase2"
  phase2_plan="$phase2_dir/plan.json"
  phase2_fake_aws="$phase2_dir/bin/aws"
  phase2_calls="$phase2_dir/calls"
  phase2_roles="$phase2_dir/roles"
  mkdir -p "$phase2_dir/bin" "$phase2_calls" "$phase2_roles"

  python3 - "$TAXONOMY" "$phase2_dir" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

taxonomy_path = Path(sys.argv[1])
root = Path(sys.argv[2])
categories = json.loads(taxonomy_path.read_text(encoding="utf-8"))

core_documents = [
    "aws_iam_role_policy.plan_reader_deny",
    "aws_iam_role_policy.plan_reader_state",
    "aws_iam_policy.task_boundary",
    "aws_iam_policy.deployer_state",
    "aws_iam_policy.deployer_ec2",
    "aws_iam_policy.deployer_elb_ecs",
    "aws_iam_policy.deployer_data",
    "aws_iam_policy.deployer_iam",
    "aws_iam_policy.deployer_guard",
    "aws_iam_role_policy.publisher",
]

mapping_policy = (
    '{"Version":"2012-10-17","Statement":['
    '{"Sid":"FixtureAllow","Effect":"Allow","Action":"s3:GetObject",'
    '"Resource":"arn:aws:s3:::orbit-infra-79s5rw-good/*"},'
    '{"Sid":"DenyReadStateObjectsOutsideScope","Effect":"Deny",'
    '"Action":"s3:GetObject",'
    '"Resource":"arn:aws:s3:::orbit-infra-79s5rw-bad/*"}]}'
)

def policy_for(address):
    if address == "aws_iam_role_policy.plan_reader_deny":
        return mapping_policy
    sid = {
        "aws_iam_role_policy.plan_reader_state": "ReadStateObjects",
        "aws_iam_policy.deployer_data": "LogsDescribeStarOnly",
        "aws_iam_role_policy.publisher": "EcrAuth",
    }.get(address, "FixtureNoop")
    return json.dumps(
        {
            "Version": "2012-10-17",
            "Statement": [{
                "Sid": sid,
                "Effect": "Allow",
                "Action": "iam:GetRole",
                "Resource": "*",
            }],
        },
        separators=(",", ":"),
    )

resources = []
for address in core_documents:
    resources.append({
        "address": address,
        "type": "aws_iam_policy" if address.startswith("aws_iam_policy.") else "aws_iam_role_policy",
        "values": {"policy": policy_for(address)},
    })
for short in ("plan_reader", "deployer", "publisher"):
    resources.append({
        "address": f"aws_iam_role.{short}",
        "type": "aws_iam_role",
        "values": {"name": f"orbit-infra-79s5rw-{short.replace('_', '-')}"},
    })
(root / "plan.json").write_text(
    json.dumps({"planned_values": {"root_module": {"resources": resources}}}, indent=2) + "\n",
    encoding="utf-8",
)

runner_vector = {
    "schema_version": 1,
    "case_id": "case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource",
    "document": "aws_iam_role_policy.plan_reader_deny",
    "sid": "DenyReadStateObjectsOutsideScope",
    "simulation_mode": "principal",
    "assertion_kind": "decision",
    "policy_source_arn": "arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-plan-reader",
    "action_names": ["s3:GetObject"],
    "resource_arns": [
        "arn:aws:s3:::orbit-infra-${SUFFIX}-good/example",
        "arn:aws:s3:::orbit-infra-${SUFFIX}-bad/example",
    ],
    "context_entries": [],
    "expect": {
        "decision": "explicitDeny",
        "resource_decisions": {
            "arn:aws:s3:::orbit-infra-${SUFFIX}-good/example": "allowed",
            "arn:aws:s3:::orbit-infra-${SUFFIX}-bad/example": "explicitDeny",
        },
        "matched_sid_required": ["FixtureAllow", "DenyReadStateObjectsOutsideScope"],
        "matched_sid_forbidden": [],
    },
}
runner_dir = root / "runner-vectors"
runner_dir.mkdir()
(runner_dir / "mapping.json").write_text(json.dumps(runner_vector, indent=2) + "\n", encoding="utf-8")

statement_starts = []
decoder = json.JSONDecoder()
statement_array = mapping_policy.index('[', mapping_policy.index('"Statement"')) + 1
cursor = statement_array
for _ in range(2):
    while mapping_policy[cursor].isspace() or mapping_policy[cursor] == ',':
        cursor += 1
    _, end = decoder.raw_decode(mapping_policy, cursor)
    statement_starts.append(cursor + 1)
    cursor = end

def position(column):
    return {"Line": 1, "Column": column}

def match(column, source="PolicyInputList.1", end_column=None):
    return {
        "SourcePolicyId": source,
        "SourcePolicyType": "IAM Policy",
        "StartPosition": position(column),
        "EndPosition": position(end_column if end_column is not None else column + 1),
    }

good = "arn:aws:s3:::orbit-infra-79s5rw-good/example"
bad = "arn:aws:s3:::orbit-infra-79s5rw-bad/example"
baseline = {
    "EvaluationResults": [{
        "EvalActionName": "s3:GetObject",
        "EvalResourceName": "arn:aws:s3:::${BucketName}/${KeyName}",
        "EvalDecision": "explicitDeny",
        "MatchedStatements": [],
        "MissingContextValues": [],
        "OrganizationsDecisionDetail": {"AllowedByOrganizations": True},
        "ResourceSpecificResults": [
            {
                "EvalResourceName": good,
                "EvalResourceDecision": "allowed",
                "MatchedStatements": [match(statement_starts[0])],
                "MissingContextValues": [],
            },
            {
                "EvalResourceName": bad,
                "EvalResourceDecision": "explicitDeny",
                "MatchedStatements": [match(statement_starts[1])],
                "MissingContextValues": [],
            },
        ],
    }],
    "IsTruncated": False,
}
(root / "response-baseline.json").write_text(json.dumps(baseline) + "\n", encoding="utf-8")

decision_mutation = json.loads(json.dumps(baseline))
decision_mutation["EvaluationResults"][0]["ResourceSpecificResults"][0]["EvalResourceDecision"] = "explicitDeny"
(root / "response-decision-mutant.json").write_text(json.dumps(decision_mutation) + "\n", encoding="utf-8")

position_mutation = json.loads(json.dumps(baseline))
position_mutation["EvaluationResults"][0]["ResourceSpecificResults"][1]["MatchedStatements"] = [match(statement_starts[0])]
(root / "response-position-mutant.json").write_text(json.dumps(position_mutation) + "\n", encoding="utf-8")

missing_mutation = json.loads(json.dumps(baseline))
missing_mutation["EvaluationResults"][0]["ResourceSpecificResults"].pop()
(root / "response-missing-arn.json").write_text(json.dumps(missing_mutation) + "\n", encoding="utf-8")

unmapped_mutation = json.loads(json.dumps(baseline))
unmapped_mutation["EvaluationResults"][0]["ResourceSpecificResults"][1]["MatchedStatements"] = [match(1)]
(root / "response-unmapped.json").write_text(json.dumps(unmapped_mutation) + "\n", encoding="utf-8")

unknown_source_mutation = json.loads(json.dumps(baseline))
unknown_source_mutation["EvaluationResults"][0]["ResourceSpecificResults"][1]["MatchedStatements"] = [
    match(statement_starts[1], "UnknownPolicyLabel")
]
(root / "response-unknown-source.json").write_text(json.dumps(unknown_source_mutation) + "\n", encoding="utf-8")

ambiguous_dir = root / "ambiguous-vectors"
ambiguous_dir.mkdir()
ambiguous_policy = '{"Version":"2012-10-17","Statement":[{"Sid":"EcrAuth","Effect":"Allow","Action":"ecr:GetAuthorizationToken","Resource":"*"},{"Sid":"Other__","Effect":"Allow","Action":"ecr:GetAuthorizationToken","Resource":"*"}]}'
ambiguous_vector = {
    "schema_version": 1,
    "case_id": "case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:in-boundary",
    "document": "aws_iam_policy.task_boundary",
    "sid": "EcrAuth",
    "simulation_mode": "custom",
    "assertion_kind": "decision",
    "policy_input_list": [ambiguous_policy],
    "action_names": ["ecr:GetAuthorizationToken"],
    "resource_arns": ["*"],
    "context_entries": [],
    "expect": {
        "decision": "allowed",
        "matched_sid_required": ["EcrAuth"],
        "matched_sid_forbidden": [],
    },
}
(ambiguous_dir / "ambiguous.json").write_text(json.dumps(ambiguous_vector, indent=2) + "\n", encoding="utf-8")
ambiguous_first = ambiguous_policy.index('{', ambiguous_policy.index('[')) + 1
ambiguous_second = ambiguous_policy.index('{', ambiguous_first) + 1
ambiguous_response = {
    "EvaluationResults": [{
        "EvalActionName": "ecr:GetAuthorizationToken",
        "EvalResourceName": "*",
        "EvalDecision": "allowed",
        "ResourceSpecificResults": [{
            "EvalResourceName": "*",
            "EvalResourceDecision": "allowed",
            "MatchedStatements": [match(ambiguous_first, "PolicyInputList.1", ambiguous_second)],
            "MissingContextValues": [],
        }],
    }],
}
(root / "response-ambiguous.json").write_text(json.dumps(ambiguous_response) + "\n", encoding="utf-8")

duplicate_dir = root / "duplicate-vectors"
duplicate_dir.mkdir()
duplicate_cases = [entry for entry in categories if entry["document"] == "aws_iam_policy.deployer_data" and entry["sid"] == "ClickhouseSecretCreateWithTag" and entry["category"] == "simulator-decision"][:2]
for index, category in enumerate(duplicate_cases):
    vector = {
        "schema_version": 1,
        "case_id": category["case_id"],
        "document": category["document"],
        "sid": category["sid"],
        "simulation_mode": "principal",
        "assertion_kind": "decision",
        "policy_source_arn": "arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-deployer",
        "action_names": ["secretsmanager:CreateSecret"],
        "resource_arns": ["arn:aws:secretsmanager:us-east-1:${ACCOUNT_ID}:secret:duplicate"],
        "context_entries": [],
        "expect": {
            "decision": "allowed",
            "matched_sid_required": [],
            "matched_sid_forbidden": [],
        },
    }
    (duplicate_dir / f"duplicate-{index}.json").write_text(json.dumps(vector, indent=2) + "\n", encoding="utf-8")

isolated_dir = root / "isolated-vectors"
isolated_dir.mkdir()
isolated = json.loads((taxonomy_path.parent / "valid-custom-isolated.json").read_text(encoding="utf-8"))
(isolated_dir / "isolated.json").write_text(json.dumps(isolated, indent=2) + "\n", encoding="utf-8")
isolated_resource = "arn:aws:logs:us-east-1:000000000000:log-group:/orbit/79s5rw/example"
isolated_response = {
    "EvaluationResults": [{
        "EvalActionName": action,
        "EvalResourceName": "arn:aws:logs:*:${Account}:log-group:${LogGroupName}",
        "EvalDecision": "implicitDeny",
        "ResourceSpecificResults": [{
            "EvalResourceName": isolated_resource,
            "EvalResourceDecision": "implicitDeny",
            "MatchedStatements": [],
            "MissingContextValues": [],
        }],
    } for action in isolated["action_names"]],
}
(root / "response-isolated.json").write_text(json.dumps(isolated_response) + "\n", encoding="utf-8")
isolated_mutant = json.loads(json.dumps(isolated_response))
for result in isolated_mutant["EvaluationResults"]:
    result["ResourceSpecificResults"][0]["EvalResourceDecision"] = "allowed"
(root / "response-isolated-mutant.json").write_text(json.dumps(isolated_mutant) + "\n", encoding="utf-8")

role_dir = root / "role-vectors"
role_dir.mkdir()
role_vectors = []
role_specs = [
    ("aws_iam_role_policy.plan_reader_state", "ReadStateObjects", "plan-reader"),
    ("aws_iam_policy.deployer_data", "LogsDescribeStarOnly", "deployer"),
    ("aws_iam_role_policy.publisher", "EcrAuth", "publisher"),
]
for index, (document, sid, role) in enumerate(role_specs):
    category = next(entry for entry in categories if entry["document"] == document and entry["sid"] == sid and entry["category"] == "simulator-decision")
    vector = {
        "schema_version": 1,
        "case_id": category["case_id"],
        "document": document,
        "sid": sid,
        "simulation_mode": "principal",
        "assertion_kind": "decision",
        "policy_source_arn": f"arn:aws:iam::${{ACCOUNT_ID}}:role/orbit-infra-${{SUFFIX}}-{role}",
        "action_names": ["iam:GetRole"],
        "resource_arns": [f"arn:aws:iam::${{ACCOUNT_ID}}:role/orbit-infra-${{SUFFIX}}-fixture-{index}"],
        "context_entries": [],
        "expect": {
            "decision": "allowed",
            "matched_sid_required": [],
            "matched_sid_forbidden": [],
        },
    }
    role_vectors.append(vector)
    (role_dir / f"role-{index}.json").write_text(json.dumps(vector, indent=2) + "\n", encoding="utf-8")

custom_records = []
for vector in role_vectors:
    policy = policy_for(vector["document"])
    custom_records.append({
        "case_id": vector["case_id"],
        "decision_observed": "allowed",
        "matched_sids": [],
        "expect": vector["expect"],
        "pass": True,
        "mode": "principal",
        "document_hashes_submitted": {
            "policy_input_list": [{"sha256": hashlib.sha256(policy.encode("utf-8")).hexdigest()}],
            "permissions_boundary_policy_input_list": [],
        },
    })
(root / "role-custom-report.json").write_text(
    json.dumps({"records": custom_records, "summary": {"total": 3, "passed": 3, "failed": 0, "runner_failures": 0}}, indent=2) + "\n",
    encoding="utf-8",
)
PY

  # The fake is the only executable named aws in these contracts. Every call
  # still traverses scripts/aws-cli.sh.
  cat >"$phase2_fake_aws" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$FAKE_AWS_CALL_DIR" "$FAKE_ROLE_STATE_DIR"
count_file="$FAKE_AWS_CALL_DIR/count"
count=0
[ ! -f "$count_file" ] || count="$(<"$count_file")"
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
python3 - "$FAKE_AWS_CALL_DIR/$count.json" "${FAKE_AWS_EXPECTED_INPUTS:-}" "$@" <<'PY'
import json
from pathlib import Path
import sys

record_path = Path(sys.argv[1])
expected_path = Path(sys.argv[2])
args = sys.argv[3:]
record_path.write_text(json.dumps(args) + "\n", encoding="utf-8")
if args[:2] != ["iam", "simulate-custom-policy"]:
    raise SystemExit(0)

expected = json.loads(expected_path.read_text(encoding="utf-8"))

def option_values(option):
    if args.count(option) != 1:
        return []
    index = args.index(option) + 1
    values = []
    while index < len(args) and not args[index].startswith("--"):
        values.append(args[index])
        index += 1
    return values

for option, key, label in (
    ("--action-names", "actions", "action names"),
    ("--resource-arns", "resources", "resource ARNs"),
):
    submitted = option_values(option)
    if sorted(submitted) != expected[key]:
        want = json.dumps(expected[key], separators=(",", ":"))
        got = json.dumps(submitted, separators=(",", ":"))
        raise SystemExit(f"FAIL: fake simulate-custom-policy {label} mismatch: expected {want}, submitted {got}")
PY

service=${1:-}
operation=${2:-}
shift 2 || true

value_after() {
  local wanted=$1
  shift
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "$wanted" ]; then
      printf '%s\n' "$2"
      return 0
    fi
    shift
  done
  return 1
}

case "$service $operation" in
  "iam simulate-custom-policy")
    simulate_file="$FAKE_AWS_CALL_DIR/simulate-count"
    simulate_count=0
    [ ! -f "$simulate_file" ] || simulate_count="$(<"$simulate_file")"
    simulate_count=$((simulate_count + 1))
    printf '%s\n' "$simulate_count" >"$simulate_file"
    if [ "${FAKE_AWS_SCENARIO:-success}" = throttle-once ] && [ "$simulate_count" -eq 1 ]; then
      echo 'An error occurred (Throttling) when calling the SimulateCustomPolicy operation' >&2
      exit 254
    fi
    if [ "${FAKE_AWS_SCENARIO:-success}" = throttle-always ]; then
      echo 'An error occurred (RequestLimitExceeded) when calling the SimulateCustomPolicy operation' >&2
      exit 254
    fi
    if [ "${FAKE_AWS_SCENARIO:-success}" = timeout ]; then
      echo 'aws-cli.sh: AWS command timed out after 30s' >&2
      exit 124
    fi
    cat "$FAKE_AWS_RESPONSE"
    ;;
  "sts get-caller-identity")
    jq -cn --arg account "${FAKE_ACCOUNT_ID:-000000000000}" '{Account:$account,Arn:("arn:aws:iam::"+$account+":root"),UserId:"fixture"}'
    ;;
  "iam create-role")
    role_name="$(value_after --role-name "$@")"
    create_file="$FAKE_AWS_CALL_DIR/create-count"
    create_count=0
    [ ! -f "$create_file" ] || create_count="$(<"$create_file")"
    create_count=$((create_count + 1))
    printf '%s\n' "$create_count" >"$create_file"
    if [ "${FAKE_AWS_SCENARIO:-}" = entity-exists ] && [ "$create_count" -eq 1 ]; then
      echo 'An error occurred (EntityAlreadyExists) when calling the CreateRole operation' >&2
      exit 254
    fi
    if [ "${FAKE_AWS_SCENARIO:-}" = create-midway ] && [ "$create_count" -eq 2 ]; then
      echo 'An error occurred (ServiceFailure) when calling the CreateRole operation' >&2
      exit 254
    fi
    tag_value="$(value_after --tags "$@" | sed 's/^Key=OrbitIamSimulationRun,Value=//')"
    jq -cn --arg tag "$tag_value" '{tag:$tag,policy:false}' >"$FAKE_ROLE_STATE_DIR/$role_name.json"
    jq -cn --arg role "$role_name" '{Role:{RoleName:$role}}'
    if [ "${FAKE_AWS_SCENARIO:-}" = term-during-create ] && [ "$create_count" -eq 1 ]; then
      kill -TERM "$IAM_SIM_LANE_PID"
    fi
    ;;
  "iam list-role-tags")
    role_name="$(value_after --role-name "$@")"
    [ -f "$FAKE_ROLE_STATE_DIR/$role_name.json" ] || {
      echo 'An error occurred (NoSuchEntity) when calling the ListRoleTags operation' >&2
      exit 254
    }
    tag_value="$(jq -r '.tag' "$FAKE_ROLE_STATE_DIR/$role_name.json")"
    if [ "${FAKE_AWS_SCENARIO:-}" = tag-mismatch ]; then
      tag_value=wrong-run
    fi
    jq -cn --arg tag "$tag_value" '{Tags:[{Key:"OrbitIamSimulationRun",Value:$tag}]}'
    ;;
  "iam put-role-policy")
    role_name="$(value_after --role-name "$@")"
    jq '.policy = true' "$FAKE_ROLE_STATE_DIR/$role_name.json" >"$FAKE_ROLE_STATE_DIR/$role_name.json.next"
    mv "$FAKE_ROLE_STATE_DIR/$role_name.json.next" "$FAKE_ROLE_STATE_DIR/$role_name.json"
    printf '{}\n'
    ;;
  "iam simulate-principal-policy")
    action="$(value_after --action-names "$@")"
    resource="$(value_after --resource-arns "$@")"
    jq -cn --arg action "$action" --arg resource "$resource" '{EvaluationResults:[{EvalActionName:$action,EvalResourceName:$resource,EvalDecision:"allowed",ResourceSpecificResults:[{EvalResourceName:$resource,EvalResourceDecision:"allowed",MatchedStatements:[],MissingContextValues:[]}]}]}'
    ;;
  "iam delete-role-policy")
    role_name="$(value_after --role-name "$@")"
    delete_policy_file="$FAKE_AWS_CALL_DIR/delete-policy-count"
    delete_policy_count=0
    [ ! -f "$delete_policy_file" ] || delete_policy_count="$(<"$delete_policy_file")"
    delete_policy_count=$((delete_policy_count + 1))
    printf '%s\n' "$delete_policy_count" >"$delete_policy_file"
    if [ "${FAKE_AWS_SCENARIO:-}" = delete-policy-fails ] && [ "$delete_policy_count" -eq 1 ]; then
      echo 'An error occurred (ServiceFailure) when calling the DeleteRolePolicy operation' >&2
      exit 254
    fi
    jq '.policy = false' "$FAKE_ROLE_STATE_DIR/$role_name.json" >"$FAKE_ROLE_STATE_DIR/$role_name.json.next"
    mv "$FAKE_ROLE_STATE_DIR/$role_name.json.next" "$FAKE_ROLE_STATE_DIR/$role_name.json"
    printf '{}\n'
    ;;
  "iam delete-role")
    role_name="$(value_after --role-name "$@")"
    if jq -e '.policy == true' "$FAKE_ROLE_STATE_DIR/$role_name.json" >/dev/null; then
      echo 'An error occurred (DeleteConflict) when calling the DeleteRole operation' >&2
      exit 254
    fi
    if [ "${FAKE_AWS_SCENARIO:-}" != verify-present ]; then
      rm -f "$FAKE_ROLE_STATE_DIR/$role_name.json"
    fi
    printf '{}\n'
    ;;
  "iam get-role")
    role_name="$(value_after --role-name "$@")"
    if [ -f "$FAKE_ROLE_STATE_DIR/$role_name.json" ]; then
      jq -cn --arg role "$role_name" '{Role:{RoleName:$role}}'
      exit 0
    fi
    echo 'An error occurred (NoSuchEntity) when calling the GetRole operation' >&2
    exit 254
    ;;
  *)
    echo "unexpected fake AWS call: $service $operation" >&2
    exit 2
    ;;
esac
FAKE
  chmod +x "$phase2_fake_aws"
}

reset_phase2_fake() {
  rm -f "$phase2_calls"/* "$phase2_roles"/*
}

phase2_call_count() {
  local service=$1
  local operation=$2
  python3 - "$phase2_calls" "$service" "$operation" <<'PY'
import json
from pathlib import Path
import sys
count = 0
for path in Path(sys.argv[1]).glob("*.json"):
    args = json.loads(path.read_text(encoding="utf-8"))
    count += args[:2] == sys.argv[2:4]
print(count)
PY
}

run_phase2_runner() {
  local scenario=$1
  local response=$2
  local vectors=$3
  local report=$4
  local expected_inputs="$phase2_dir/expected-custom-inputs.json"
  shift 4
  python3 - "$vectors" "$expected_inputs" "$@" <<'PY'
import json
from pathlib import Path
import sys

vector_dir = Path(sys.argv[1])
output_path = Path(sys.argv[2])
remaining = sys.argv[3:]
only = remaining[remaining.index("--only") + 1] if "--only" in remaining else None
vectors = [
    json.loads(path.read_text(encoding="utf-8"))
    for path in sorted(vector_dir.rglob("*.json"))
]
if only is not None:
    vectors = [vector for vector in vectors if vector["case_id"] == only]

def render(value):
    return value.replace("${ACCOUNT_ID}", "000000000000").replace("${SUFFIX}", "79s5rw")

expected = {
    "actions": sorted({render(action) for vector in vectors for action in vector["action_names"]}),
    "resources": sorted({render(resource) for vector in vectors for resource in vector["resource_arns"]}),
}
output_path.write_text(json.dumps(expected, sort_keys=True) + "\n", encoding="utf-8")
PY
  env \
    PATH="$phase2_dir/bin:$PATH" \
    AWS_CLI_BIN=aws \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
    FAKE_AWS_CALL_DIR="$phase2_calls" \
    FAKE_ROLE_STATE_DIR="$phase2_roles" \
    FAKE_AWS_SCENARIO="$scenario" \
    FAKE_AWS_RESPONSE="$response" \
    FAKE_AWS_EXPECTED_INPUTS="$expected_inputs" \
    IAM_SIM_RETRY_BASE_SECONDS=0 \
    TARGET=aws \
    "$IAM_SIM_RUNNER" --plan "$phase2_plan" --vectors "$vectors" --report "$report" "$@"
}

expect_runner_failure() {
  local label=$1
  local expected=$2
  local scenario=$3
  local response=$4
  local vectors=$5
  shift 5
  local output rc fail_line report="$phase2_dir/failure-${label// /-}.json"
  reset_phase2_fake
  set +e
  output="$(run_phase2_runner "$scenario" "$response" "$vectors" "$report" "$@" 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && [ -n "$fail_line" ] && grep -Fq "$expected" <<<"$output"; then
    pass_case "$label mutation -> $fail_line"
  else
    fail_case "$label mutation did not fail as required" "rc=$rc output=$output"
  fi
}

run_iam_simulate_runner_contracts() {
  local output report isolated_policy
  echo "== iam simulate contracts: RUNNER =="
  group_failures=$failures
  phase2_setup

  if [ ! -x "$IAM_SIM_RUNNER" ]; then
    fail_case "custom-lane runner exists and is executable" "$IAM_SIM_RUNNER is missing"
  else
    reset_phase2_fake
    report="$phase2_dir/runner-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-baseline.json" "$phase2_dir/runner-vectors" "$report" 2>&1)" && \
       jq -e '
         .records | length == 1
         and .[0].decision_observed == {"arn:aws:s3:::orbit-infra-79s5rw-bad/example":"explicitDeny","arn:aws:s3:::orbit-infra-79s5rw-good/example":"allowed"}
         and .[0].matched_sids == ["DenyReadStateObjectsOutsideScope","FixtureAllow"]
         and .[0].pass == true
         and (.[0].document_hashes_submitted.policy_input_list | length) == 1
       ' "$report" >/dev/null; then
      pass_case "runner maps nested per-resource decisions and source positions"
    else
      fail_case "runner maps nested per-resource decisions and source positions" "$output"
    fi

    expect_runner_failure "runner per-resource mapper" "decision mismatch" \
      success "$phase2_dir/response-decision-mutant.json" "$phase2_dir/runner-vectors"
    expect_runner_failure "runner position-to-Sid attribution" "required matched Sid is absent" \
      success "$phase2_dir/response-position-mutant.json" "$phase2_dir/runner-vectors"
    expect_runner_failure "runner ambiguous position refusal" "ambiguous matched statement position" \
      success "$phase2_dir/response-ambiguous.json" "$phase2_dir/ambiguous-vectors"
    expect_runner_failure "runner unmapped position refusal" "unmapped matched statement position from PolicyInputList.1" \
      success "$phase2_dir/response-unmapped.json" "$phase2_dir/runner-vectors"
    expect_runner_failure "runner unknown source-label refusal" \
      "unrecognised SourcePolicyId UnknownPolicyLabel; submitted labels: PolicyInputList.1" \
      success "$phase2_dir/response-unknown-source.json" "$phase2_dir/runner-vectors"
    expect_runner_failure "runner missing submitted ARN refusal" "submitted resource ARN is absent" \
      success "$phase2_dir/response-missing-arn.json" "$phase2_dir/runner-vectors"

    expect_runner_failure "runner duplicate pair pre-call refusal" "duplicate action/resource pair in batch" \
      success "$phase2_dir/response-baseline.json" "$phase2_dir/duplicate-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 0 ]; then
      fail_case "runner duplicate pair pre-call refusal" "fake AWS was called"
    elif ! jq -e '. as $report | (($report.records | length) == 2 and all($report.records[]; .decision_observed == null and (.runner_failure | contains("duplicate action/resource pair"))) and $report.summary.runner_failures == 2)' \
      "$phase2_dir/failure-runner-duplicate-pair-pre-call-refusal.json" >/dev/null; then
      fail_case "runner duplicate pair pre-call refusal" "failure report is incomplete"
    fi

    reset_phase2_fake
    report="$phase2_dir/throttle-report.json"
    if output="$(run_phase2_runner throttle-once "$phase2_dir/response-baseline.json" "$phase2_dir/runner-vectors" "$report" 2>&1)" && \
       [ "$(phase2_call_count iam simulate-custom-policy)" -eq 2 ]; then
      pass_case "runner retries throttling once and then succeeds"
    else
      fail_case "runner retries throttling once and then succeeds" "$output"
    fi
    expect_runner_failure "runner throttle attempt cap" "failed after 5 attempts" \
      throttle-always "$phase2_dir/response-baseline.json" "$phase2_dir/runner-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 5 ]; then
      fail_case "runner throttle attempt cap" "expected 5 fake calls"
    fi

    expect_runner_failure "runner timeout no-retry" "timed out with exit 124" \
      timeout "$phase2_dir/response-baseline.json" "$phase2_dir/runner-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 1 ]; then
      fail_case "runner timeout no-retry" "timeout was retried"
    elif ! jq -e '. as $report | (($report.records | length) == 1 and $report.records[0].decision_observed == null and $report.records[0].runner_failure == "AWS simulator timed out with exit 124" and $report.summary.runner_failures == 1)' \
      "$phase2_dir/failure-runner-timeout-no-retry.json" >/dev/null; then
      fail_case "runner timeout no-retry" "timeout was recorded as a decision"
    fi

    reset_phase2_fake
    set +e
    output="$(env PATH="$phase2_dir/bin:$PATH" AWS_CLI_BIN=aws AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
      FAKE_AWS_CALL_DIR="$phase2_calls" FAKE_ROLE_STATE_DIR="$phase2_roles" \
      TARGET=localstack "$IAM_SIM_RUNNER" --plan "$phase2_plan" \
      --vectors "$phase2_dir/runner-vectors" --report "$phase2_dir/target.json" 2>&1)"
    target_rc=$?
    set -e
    if [ "$target_rc" -ne 0 ] && grep -Fq 'FAIL: TARGET must be exactly aws' <<<"$output" && \
       [ "$(phase2_call_count iam simulate-custom-policy)" -eq 0 ]; then
      pass_case "runner TARGET refusal mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "runner TARGET refusal mutation did not fail as required" "$output"
    fi

    reset_phase2_fake
    report="$phase2_dir/isolated-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-isolated.json" "$phase2_dir/isolated-vectors" "$report" 2>&1)"; then
      isolated_policy="$(python3 - "$phase2_calls" <<'PY'
import json
from pathlib import Path
import sys
for path in Path(sys.argv[1]).glob("*.json"):
    args = json.loads(path.read_text(encoding="utf-8"))
    if args[:2] == ["iam", "simulate-custom-policy"]:
        index = args.index("--policy-input-list")
        print(args[index + 1])
        break
PY
)"
      if jq -e '.Statement | length == 1 and .[0].Sid == "LogsCreateWithTag"' <<<"$isolated_policy" >/dev/null; then
        pass_case "runner wraps an isolated vector as one statement"
      else
        fail_case "runner wraps an isolated vector as one statement" "$isolated_policy"
      fi
    else
      fail_case "runner wraps an isolated vector as one statement" "$output"
    fi
    expect_runner_failure "runner isolated one-statement decision" "decision mismatch" \
      success "$phase2_dir/response-isolated-mutant.json" "$phase2_dir/isolated-vectors"

    runner_mutant="$phase2_dir/iam-simulate-wrong-resource.sh"
    python3 - "$IAM_SIM_RUNNER" "$runner_mutant" "$REPO_ROOT" <<'PY_MUTANT'
from pathlib import Path
import shlex
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
resource_line = 'resources = sorted({resource for item in batch for resource in item["vector"]["resource_arns"]})'
if source.count(root_line) != 1 or source.count(resource_line) != 1:
    raise SystemExit("FAIL: runner wrong-resource mutation anchors changed")
source = source.replace(root_line, f"REPO_ROOT={shlex.quote(sys.argv[3])}")
source = source.replace(resource_line, 'resources = ["arn:aws:s3:::orbit-infra-wrong/example"]')
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY_MUTANT
    chmod +x "$runner_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_RUNNER="$runner_mutant" run_phase2_runner \
      success "$phase2_dir/response-baseline.json" "$phase2_dir/runner-vectors" \
      "$phase2_dir/wrong-resource-report.json" 2>&1)"
    mutant_rc=$?
    set -e
    if [ "$mutant_rc" -ne 0 ] && \
       grep -Fq 'FAIL: fake simulate-custom-policy resource ARNs mismatch:' <<<"$output"; then
      pass_case "runner fake resource-set enforcement mutation -> $(grep -m1 'FAIL: fake simulate-custom-policy resource ARNs mismatch:' <<<"$output")"
    else
      fail_case "runner fake resource-set enforcement mutation did not fail as required" "rc=$mutant_rc output=$output"
    fi
  fi

  if [ "$failures" -eq "$group_failures" ]; then
    echo "PASS: IAM simulate RUNNER group"
  else
    echo "FAIL: IAM simulate RUNNER group" >&2
  fi
}

run_phase2_role_lane() {
  local scenario=$1
  shift
  env \
    PATH="$phase2_dir/bin:$PATH" \
    AWS_CLI_BIN=aws \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
    FAKE_AWS_CALL_DIR="$phase2_calls" \
    FAKE_ROLE_STATE_DIR="$phase2_roles" \
    FAKE_AWS_SCENARIO="$scenario" \
    FAKE_ACCOUNT_ID=000000000000 \
    IAM_SIM_RUN_ID=fixture-run \
    TARGET=aws \
    "$IAM_SIM_ROLE_LANE" --plan "$phase2_plan" --vectors "$phase2_dir/role-vectors" \
      --report "$phase2_dir/role-report.json" --expect-account 000000000000 \
      --custom-report "$phase2_dir/role-custom-report.json" "$@"
}

expect_role_failure() {
  local label=$1
  local expected=$2
  local scenario=$3
  shift 3
  local output rc fail_line
  reset_phase2_fake
  set +e
  output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    run_phase2_role_lane "$scenario" "$@" 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && [ -n "$fail_line" ] && grep -Fq "$expected" <<<"$output"; then
    pass_case "$label mutation -> $fail_line"
  else
    fail_case "$label mutation did not fail as required" "rc=$rc output=$output"
  fi
}

validate_dry_run_inventory() {
  local inventory=$1
  local operation expected
  for operation in create-role put-role-policy delete-role-policy delete-role; do
    expected=3
    if [ "$(grep -Ec "iam $operation( |$)" <<<"$inventory" || true)" -ne "$expected" ]; then
      echo "FAIL: dry-run inventory requires three iam $operation calls" >&2
      return 1
    fi
  done
  if [ "$(grep -c 'iam simulate-principal-policy' <<<"$inventory" || true)" -ne 6 ] ||
     [ "$(grep -c 'iam list-role-tags' <<<"$inventory" || true)" -ne 9 ] ||
     [ "$(grep -c 'iam get-role' <<<"$inventory" || true)" -ne 3 ]; then
    echo "FAIL: dry-run inventory requires simulations, ownership reads, and absence checks" >&2
    return 1
  fi
  python3 - "$inventory" <<'PY'
import re
import sys
lines = sys.argv[1].splitlines()

def positions(operation):
    return [index for index, line in enumerate(lines) if re.search(rf" iam {operation}(?: |$)", line)]

creates = positions("create-role")
puts = positions("put-role-policy")
simulates = positions("simulate-principal-policy")
delete_policies = positions("delete-role-policy")
delete_roles = positions("delete-role")
if not (max(creates) < min(puts) < max(puts) < min(simulates) and max(simulates) < min(delete_policies)):
    raise SystemExit("FAIL: dry-run inventory phase ordering is wrong")
if any(policy >= role for policy, role in zip(delete_policies, delete_roles)):
    raise SystemExit("FAIL: dry-run inventory must delete each inline policy before its role")
PY
}

run_iam_simulate_role_lane_contracts() {
  local output rc mutated_inventory
  echo "== iam simulate contracts: ROLE-LANE =="
  group_failures=$failures

  if [ ! -x "$IAM_SIM_ROLE_LANE" ]; then
    fail_case "role-lane runner exists and is executable" "$IAM_SIM_ROLE_LANE is missing"
  else
    reset_phase2_fake
    if output="$(run_phase2_role_lane success --dry-run 2>&1)" && \
       validate_dry_run_inventory "$output" && \
       [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
      pass_case "role-lane dry-run prints the full inventory with zero calls"
    else
      fail_case "role-lane dry-run prints the full inventory with zero calls" "$output"
    fi
    mutated_inventory="$(grep -v 'iam delete-role-policy' <<<"$output" || true)"
    expect_failure "role-lane dry-run inventory" "requires three iam delete-role-policy calls" \
      validate_dry_run_inventory "$mutated_inventory"

    reset_phase2_fake
    set +e
    output="$(run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fq 'FAIL: IAM_SIM_LANE_CONFIRM must equal create-real-iam-resources' <<<"$output" && \
       [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
      pass_case "role-lane opt-in refusal mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane opt-in refusal mutation did not fail as required" "$output"
    fi

    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      env PATH="$phase2_dir/bin:$PATH" AWS_CLI_BIN=aws AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
      FAKE_AWS_CALL_DIR="$phase2_calls" FAKE_ROLE_STATE_DIR="$phase2_roles" \
      FAKE_AWS_SCENARIO=success FAKE_ACCOUNT_ID=111111111111 IAM_SIM_RUN_ID=fixture-run \
      TARGET=aws "$IAM_SIM_ROLE_LANE" --plan "$phase2_plan" --vectors "$phase2_dir/role-vectors" \
      --report "$phase2_dir/mismatch.json" --expect-account 000000000000 \
      --custom-report "$phase2_dir/role-custom-report.json" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fq 'FAIL: caller account mismatch' <<<"$output" && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane account mismatch refusal mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane account mismatch refusal mutation did not fail as required" "$output"
    fi

    expect_role_failure "role-lane tag mismatch pre-mutation refusal" "ownership tag mismatch" tag-mismatch
    if [ "$(phase2_call_count iam put-role-policy)" -ne 0 ] || \
       [ "$(phase2_call_count iam delete-role)" -ne 0 ]; then
      fail_case "role-lane tag mismatch pre-mutation refusal" "a mutation ran after tag mismatch"
    fi

    expect_role_failure "role-lane EntityAlreadyExists isolation" "manual cleanup: role already existed at create time" entity-exists
    if [ "$(phase2_call_count iam delete-role-policy)" -ne 0 ] || \
       [ "$(phase2_call_count iam delete-role)" -ne 0 ]; then
      fail_case "role-lane EntityAlreadyExists isolation" "collision caused a delete"
    fi

    expect_role_failure "role-lane midway create cleanup" "create-role failed" create-midway
    if find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      fail_case "role-lane midway create cleanup" "created role residue remains"
    fi

    expect_role_failure "role-lane delete-policy barrier" "manual cleanup: delete-role-policy failed" delete-policy-fails
    if python3 - "$phase2_calls" <<'PY'
import json
from pathlib import Path
import sys
calls = [json.loads(path.read_text()) for path in sorted(Path(sys.argv[1]).glob("*.json"), key=lambda path: int(path.stem))]
failed_role = next(call[call.index("--role-name") + 1] for call in calls if call[:2] == ["iam", "delete-role-policy"])
raise SystemExit(any(call[:2] == ["iam", "delete-role"] and call[call.index("--role-name") + 1] == failed_role for call in calls))
PY
    then
      :
    else
      fail_case "role-lane delete-policy barrier" "role delete followed the failed policy delete"
    fi

    expect_role_failure "role-lane TERM cleanup" "terminated by TERM" term-during-create
    if find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      fail_case "role-lane TERM cleanup" "TERM left role residue"
    fi

    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      run_phase2_role_lane success 2>&1)" && \
       [ "$(phase2_call_count iam get-role)" -eq 3 ] && \
       ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      pass_case "role-lane verifies NoSuchEntity after cleanup"
    else
      fail_case "role-lane verifies NoSuchEntity after cleanup" "$output"
    fi
    expect_role_failure "role-lane post-cleanup verification" "manual cleanup: role still exists" verify-present
  fi

  if [ "$failures" -eq "$group_failures" ]; then
    echo "PASS: IAM simulate ROLE-LANE group"
  else
    echo "FAIL: IAM simulate ROLE-LANE group" >&2
  fi
}
