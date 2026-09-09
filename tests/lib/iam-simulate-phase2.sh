#!/usr/bin/env bash
# shellcheck disable=SC2154 # Globals are provided by the sourcing contract suite.

# Phase-2 IAM simulator contracts. This file is sourced by
# tests/iam-simulate-contracts.sh so it shares that suite's result counters and
# temporary directory.

IAM_SIM_RUNNER="$REPO_ROOT/scripts/iam-simulate.sh"
IAM_SIM_ROLE_LANE="$REPO_ROOT/scripts/iam-simulate-roles.sh"
IAM_SIM_CORE="$REPO_ROOT/scripts/iam_simulate_core.py"
IAM_SIM_AWS_WRAPPER="$REPO_ROOT/scripts/aws-cli.sh"

phase2_setup() {
  phase2_dir="$tmp_dir/phase2"
  phase2_plan="$phase2_dir/plan.json"
  phase2_fake_aws="$phase2_dir/bin/aws"
  phase2_calls="$phase2_dir/calls"
  phase2_roles="$phase2_dir/roles"
  mkdir -p "$phase2_dir/bin" "$phase2_calls" "$phase2_roles"

  python3 - "$TAXONOMY" "$phase2_dir" \
    "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" <<'PY'
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

taxonomy_path = Path(sys.argv[1])
root = Path(sys.argv[2])
role_projection_plan_source = Path(sys.argv[3])
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

real_position_policy = (
    '{"Version":"2012-10-17","Statement":['
    '{"Action":["s3:GetObjectVersion","s3:GetObject"],"Effect":"Deny",'
    '"NotResource":["arn:aws:s3:::orbit-infra-79s5rw-tfstate/envs/preview/*",'
    '"arn:aws:s3:::orbit-infra-79s5rw-tfstate/bootstrap/*"],'
    '"Sid":"DenyReadStateObjectsOutsideScope"},'
    '{"Action":"s3:ListBucket","Effect":"Deny",'
    '"NotResource":"arn:aws:s3:::orbit-infra-79s5rw-tfstate",'
    '"Sid":"DenyListBucketOutsideScope"},'
    '{"Action":["s3:ListBucketVersions","s3:ListBucket"],'
    '"Condition":{"StringNotLike":{"s3:prefix":['
    '"envs/preview/*","bootstrap/*","envs/preview","bootstrap"]}},'
    '"Effect":"Deny","Resource":"arn:aws:s3:::orbit-infra-79s5rw-tfstate",'
    '"Sid":"DenyListBucketOutsideScopePrefix"},'
    '{"Action":["s3:ListBucketVersions","s3:ListBucket"],'
    '"Condition":{"Null":{"s3:prefix":"true"}},"Effect":"Deny",'
    '"Resource":"arn:aws:s3:::orbit-infra-79s5rw-tfstate",'
    '"Sid":"DenyListBucketMissingPrefix"},'
    '{"Action":["ssm:GetParametersByPath","ssm:GetParameters",'
    '"ssm:GetParameterHistory","ssm:GetParameter",'
    '"secretsmanager:GetSecretValue","lambda:GetLayerVersion",'
    '"lambda:GetFunctionConfiguration","lambda:GetFunction","kms:Decrypt"],'
    '"Effect":"Deny","Resource":"*","Sid":"DenySecretsAndParams"}]}'
)
if len(real_position_policy) != 1163 or hashlib.sha256(
    real_position_policy.encode("utf-8")
).hexdigest() != "f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b":
    raise SystemExit("FAIL: real position policy fixture bytes changed")

multiline_position_policy = """{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid":"FixtureAllow","Effect":"Allow","Action":"s3:GetObject","Resource":"*"},
    {"Action":"s3:GetObject","Effect":"Deny","Resource":"*","Sid":"DenyReadStateObjectsOutsideScope"}
  ]
}"""

scanner_position_policy = json.dumps(
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "DenyReadStateObjectsOutsideScope",
                "Effect": "Allow",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::orbit-infra-79s5rw-delimiters/*",
                "Condition": {
                    "StringEquals": {
                        "test:Value": "literal { and } and [ stay inside this string",
                    },
                },
            },
            {
                "Sid": "DenyListBucketOutsideScope",
                "Effect": "Allow",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::orbit-infra-79s5rw-escaped/*",
                "Condition": {
                    "StringEquals": {
                        "test:Value": 'an escaped "quote } [" stays inside this string',
                    },
                },
            },
        ],
    },
    separators=(",", ":"),
)
if r'\"' not in scanner_position_policy:
    raise SystemExit("FAIL: scanner position fixture lacks an escaped quote")

ambiguous_policy = '{"Version":"2012-10-17","Statement":[{"Sid":"EcrAuth","Effect":"Allow","Action":"ecr:GetAuthorizationToken","Resource":"*"},{"Sid":"Other__","Effect":"Allow","Action":"ecr:GetAuthorizationToken","Resource":"*"}]}'
isolated_plan_policy = json.dumps(
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "LogsDescribeStarOnly",
                "Effect": "Allow",
                "Action": "logs:DescribeLogGroups",
                "Resource": "*",
            },
            {
                "Sid": "LogsCreateWithTag",
                "Effect": "Allow",
                "Action": ["logs:CreateLogGroup", "logs:TagResource"],
                "Resource": "arn:aws:logs:*:000000000000:log-group:/orbit/79s5rw/*",
                "Condition": {
                    "StringEquals": {"aws:RequestTag/Project": "orbit-infra"},
                },
            },
        ],
    },
    separators=(",", ":"),
)


def policy_for(address):
    if address == "aws_iam_role_policy.plan_reader_deny":
        return mapping_policy
    if address == "aws_iam_policy.task_boundary":
        return ambiguous_policy
    if address == "aws_iam_policy.deployer_data":
        return isolated_plan_policy
    sid = {
        "aws_iam_role_policy.plan_reader_state": "ReadStateObjects",
        "aws_iam_policy.deployer_state": "FixtureDeployerState",
        "aws_iam_policy.deployer_ec2": "FixtureDeployerEc2",
        "aws_iam_policy.deployer_elb_ecs": "FixtureDeployerElbEcs",
        "aws_iam_policy.deployer_iam": "FixtureDeployerIam",
        "aws_iam_policy.deployer_guard": "FixtureDeployerGuard",
        "aws_iam_role_policy.publisher": "EcrAuth",
    }[address]
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
plan = {"planned_values": {"root_module": {"resources": resources}}}
(root / "plan.json").write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")

for name, policy in (
    ("real-position", real_position_policy),
    ("multiline-position", multiline_position_policy),
    ("scanner-position", scanner_position_policy),
):
    position_plan = deepcopy(plan)
    resource = next(
        item
        for item in position_plan["planned_values"]["root_module"]["resources"]
        if item["address"] == "aws_iam_role_policy.plan_reader_deny"
    )
    resource["values"]["policy"] = policy
    (root / f"plan-{name}.json").write_text(
        json.dumps(position_plan, indent=2) + "\n",
        encoding="utf-8",
    )

missing_document_plan = deepcopy(plan)
missing_document_plan["planned_values"]["root_module"]["resources"] = [
    resource
    for resource in missing_document_plan["planned_values"]["root_module"]["resources"]
    if resource["address"] != "aws_iam_policy.task_boundary"
]
(root / "plan-missing-document.json").write_text(
    json.dumps(missing_document_plan, indent=2) + "\n",
    encoding="utf-8",
)

missing_sid_plan = deepcopy(plan)
duplicate_sid_plan = deepcopy(plan)
for candidate, duplicate in ((missing_sid_plan, False), (duplicate_sid_plan, True)):
    resource = next(
        item
        for item in candidate["planned_values"]["root_module"]["resources"]
        if item["address"] == "aws_iam_policy.deployer_data"
    )
    policy = json.loads(isolated_plan_policy)
    if duplicate:
        policy["Statement"].append(deepcopy(policy["Statement"][1]))
    else:
        policy["Statement"] = [policy["Statement"][0]]
    resource["values"]["policy"] = json.dumps(policy, separators=(",", ":"))
(root / "plan-missing-sid.json").write_text(
    json.dumps(missing_sid_plan, indent=2) + "\n",
    encoding="utf-8",
)
(root / "plan-duplicate-sid.json").write_text(
    json.dumps(duplicate_sid_plan, indent=2) + "\n",
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

real_position_vector = {
    "schema_version": 1,
    "case_id": "case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource",
    "document": "aws_iam_role_policy.plan_reader_deny",
    "sid": "DenyReadStateObjectsOutsideScope",
    "simulation_mode": "custom",
    "assertion_kind": "decision",
    "action_names": ["s3:GetObject"],
    "resource_arns": ["arn:aws:s3:::orbit-infra-${SUFFIX}-tfstate/other/x"],
    "context_entries": [],
    "expect": {
        "decision": "explicitDeny",
        "matched_sid_required": ["DenyReadStateObjectsOutsideScope"],
        "matched_sid_forbidden": [],
    },
}
for name in ("real-position", "multiline-position"):
    position_dir = root / f"{name}-vectors"
    position_dir.mkdir()
    (position_dir / "position.json").write_text(
        json.dumps(real_position_vector, indent=2) + "\n",
        encoding="utf-8",
    )

scanner_vectors = (
    (
        "string-delimiters",
        "DenyReadStateObjectsOutsideScope",
        "case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource",
        "arn:aws:s3:::orbit-infra-${SUFFIX}-delimiters/example",
    ),
    (
        "escaped-quotes",
        "DenyListBucketOutsideScope",
        "case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:protected-resource",
        "arn:aws:s3:::orbit-infra-${SUFFIX}-escaped/example",
    ),
)
for name, sid, case_id, resource_arn in scanner_vectors:
    scanner_dir = root / f"scanner-{name}-vectors"
    scanner_dir.mkdir()
    scanner_vector = deepcopy(real_position_vector)
    scanner_vector["case_id"] = case_id
    scanner_vector["sid"] = sid
    scanner_vector["resource_arns"] = [resource_arn]
    scanner_vector["expect"] = {
        "decision": "allowed",
        "matched_sid_required": [sid],
        "matched_sid_forbidden": [],
    }
    (scanner_dir / "position.json").write_text(
        json.dumps(scanner_vector, indent=2) + "\n",
        encoding="utf-8",
    )

decoder = json.JSONDecoder()


def fixture_statement_spans(policy):
    spans = []
    cursor = policy.index('[', policy.index('"Statement"')) + 1
    while True:
        while policy[cursor].isspace() or policy[cursor] == ',':
            cursor += 1
        if policy[cursor] == ']':
            return spans
        statement, end = decoder.raw_decode(policy, cursor)
        spans.append((cursor, end, statement["Sid"]))
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


def delimiter_inclusive_match(policy, statement_index, source="PolicyInputList.1"):
    spans = fixture_statement_spans(policy)
    start, end, _ = spans[statement_index]
    start_offset = start if statement_index == 0 else start - 1
    return match(start_offset + 1, source, end + 1)


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
                "MatchedStatements": [delimiter_inclusive_match(mapping_policy, 0)],
                "MissingContextValues": [],
            },
            {
                "EvalResourceName": bad,
                "EvalResourceDecision": "explicitDeny",
                "MatchedStatements": [delimiter_inclusive_match(mapping_policy, 1)],
                "MissingContextValues": [],
            },
        ],
    }],
    "IsTruncated": False,
}
(root / "response-baseline.json").write_text(json.dumps(baseline) + "\n", encoding="utf-8")

multiple_concrete_action_level = deepcopy(baseline)
multiple_concrete_action_level["EvaluationResults"][0].pop("ResourceSpecificResults")
(root / "response-multiple-concrete-action-level.json").write_text(
    json.dumps(multiple_concrete_action_level) + "\n",
    encoding="utf-8",
)

real_position_resource = "arn:aws:s3:::orbit-infra-79s5rw-tfstate/other/x"


def position_response(start, end):
    return {
        "EvaluationResults": [{
            "EvalActionName": "s3:GetObject",
            "EvalResourceName": real_position_resource,
            "EvalDecision": "explicitDeny",
            "ResourceSpecificResults": [{
                "EvalResourceName": real_position_resource,
                "EvalResourceDecision": "explicitDeny",
                "MatchedStatements": [{
                    "SourcePolicyId": "PolicyInputList.1",
                    "SourcePolicyType": "IAM Policy",
                    "StartPosition": start,
                    "EndPosition": end,
                }],
                "MissingContextValues": [],
            }],
        }],
    }


(root / "response-real-position.json").write_text(
    json.dumps(position_response(position(38), position(271))) + "\n",
    encoding="utf-8",
)
(root / "response-multiline-position.json").write_text(
    json.dumps(
        position_response(
            {"Line": 5, "Column": 5}, {"Line": 5, "Column": 102}
        )
    ) + "\n",
    encoding="utf-8",
)


def scanner_position_response(statement_index, resource):
    _, _, sid = fixture_statement_spans(scanner_position_policy)[statement_index]
    return {
        "EvaluationResults": [{
            "EvalActionName": "s3:GetObject",
            "EvalResourceName": resource,
            "EvalDecision": "allowed",
            "ResourceSpecificResults": [{
                "EvalResourceName": resource,
                "EvalResourceDecision": "allowed",
                "MatchedStatements": [
                    delimiter_inclusive_match(scanner_position_policy, statement_index)
                ],
                "MissingContextValues": [],
            }],
        }],
        "expected_sid": sid,
    }


for index, (name, expected_sid, _, resource_template) in enumerate(scanner_vectors):
    resource = resource_template.replace("${SUFFIX}", "79s5rw")
    scanner_response = scanner_position_response(index, resource)
    if scanner_response.pop("expected_sid") != expected_sid:
        raise SystemExit(f"FAIL: scanner {name} response points at the wrong Sid")
    (root / f"response-scanner-{name}.json").write_text(
        json.dumps(scanner_response) + "\n",
        encoding="utf-8",
    )

real_plan = json.loads(
    (
        taxonomy_path.parent.parent / "iam-matrix" / "base-plan.json"
    ).read_text(encoding="utf-8")
)
real_deployer_policy = next(
    item["values"]["policy"]
    for item in real_plan["planned_values"]["root_module"]["resources"]
    if item.get("address") == "aws_iam_policy.deployer_data"
)
real_deployer_spans = fixture_statement_spans(real_deployer_policy)
if (
    len(real_deployer_policy) != 5682
    or len(real_deployer_spans) != 18
    or hashlib.sha256(real_deployer_policy.encode("utf-8")).hexdigest()
    != "dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40"
):
    raise SystemExit("FAIL: real deployer_data position fixture changed")
offset_1779_sids = [
    sid for start, end, sid in real_deployer_spans if start <= 1779 < end
]
if offset_1779_sids != ["ClickhouseSecretCreateWithTag"]:
    raise SystemExit(
        f"FAIL: real deployer_data offset 1779 owner changed: {offset_1779_sids}"
    )

deployer_position_dir = root / "deployer-position-vectors"
deployer_position_dir.mkdir()
deployer_position_vector = {
    "schema_version": 1,
    "case_id": "case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching",
    "document": "aws_iam_policy.deployer_data",
    "sid": "ClickhouseSecretCreateWithTag",
    "simulation_mode": "custom",
    "assertion_kind": "decision",
    "action_names": ["secretsmanager:CreateSecret"],
    "resource_arns": [
        "arn:aws:secretsmanager:us-east-1:${ACCOUNT_ID}:secret:orbit-infra-${SUFFIX}-x"
    ],
    "context_entries": [{
        "ContextKeyName": "aws:RequestTag/Project",
        "ContextKeyValues": ["orbit-infra"],
        "ContextKeyType": "string",
    }],
    "expect": {
        "decision": "allowed",
        "matched_sid_required": ["ClickhouseSecretCreateWithTag"],
        "matched_sid_forbidden": [],
    },
}
(deployer_position_dir / "position.json").write_text(
    json.dumps(deployer_position_vector, indent=2) + "\n",
    encoding="utf-8",
)
deployer_resource = (
    "arn:aws:secretsmanager:us-east-1:000000000000:"
    "secret:orbit-infra-79s5rw-x"
)
deployer_position_response = {
    "EvaluationResults": [{
        "EvalActionName": "secretsmanager:CreateSecret",
        "EvalResourceName": deployer_resource,
        "EvalDecision": "allowed",
        "ResourceSpecificResults": [{
            "EvalResourceName": deployer_resource,
            "EvalResourceDecision": "allowed",
            "MatchedStatements": [match(1779, end_column=2055)],
            "MissingContextValues": [],
        }],
    }],
}
(root / "response-deployer-position.json").write_text(
    json.dumps(deployer_position_response) + "\n",
    encoding="utf-8",
)
deployer_ambiguous_response = deepcopy(deployer_position_response)
deployer_ambiguous_response["EvaluationResults"][0]["ResourceSpecificResults"][0][
    "MatchedStatements"
] = [match(1778, end_column=2055)]
(root / "response-deployer-ambiguous.json").write_text(
    json.dumps(deployer_ambiguous_response) + "\n",
    encoding="utf-8",
)

decision_mutation = json.loads(json.dumps(baseline))
decision_mutation["EvaluationResults"][0]["ResourceSpecificResults"][0]["EvalResourceDecision"] = "explicitDeny"
(root / "response-decision-mutant.json").write_text(json.dumps(decision_mutation) + "\n", encoding="utf-8")

position_mutation = json.loads(json.dumps(baseline))
position_mutation["EvaluationResults"][0]["ResourceSpecificResults"][1]["MatchedStatements"] = [
    delimiter_inclusive_match(mapping_policy, 0)
]
(root / "response-position-mutant.json").write_text(json.dumps(position_mutation) + "\n", encoding="utf-8")

missing_mutation = json.loads(json.dumps(baseline))
missing_mutation["EvaluationResults"][0]["ResourceSpecificResults"].pop()
(root / "response-missing-arn.json").write_text(json.dumps(missing_mutation) + "\n", encoding="utf-8")

unmapped_mutation = json.loads(json.dumps(baseline))
unmapped_mutation["EvaluationResults"][0]["ResourceSpecificResults"][1]["MatchedStatements"] = [match(1)]
(root / "response-unmapped.json").write_text(json.dumps(unmapped_mutation) + "\n", encoding="utf-8")

unknown_source_mutation = json.loads(json.dumps(baseline))
unknown_source_mutation["EvaluationResults"][0]["ResourceSpecificResults"][1]["MatchedStatements"] = [
    delimiter_inclusive_match(mapping_policy, 1, "UnknownPolicyLabel")
]
(root / "response-unknown-source.json").write_text(json.dumps(unknown_source_mutation) + "\n", encoding="utf-8")

ambiguous_dir = root / "ambiguous-vectors"
ambiguous_dir.mkdir()
ambiguous_vector = {
    "schema_version": 1,
    "case_id": "case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:in-boundary",
    "document": "aws_iam_policy.task_boundary",
    "sid": "EcrAuth",
    "simulation_mode": "custom",
    "assertion_kind": "decision",
    "permissions_boundary_policy_input_list": ["aws_iam_policy.task_boundary"],
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
            "MatchedStatements": [match(ambiguous_first, "PolicyInputList.1", ambiguous_second + 1)],
            "MissingContextValues": [],
        }],
    }],
}
(root / "response-ambiguous.json").write_text(json.dumps(ambiguous_response) + "\n", encoding="utf-8")
resolved_response = deepcopy(ambiguous_response)
resolved_response["EvaluationResults"][0]["ResourceSpecificResults"][0]["MatchedStatements"] = [
    match(ambiguous_first)
]
(root / "response-resolved.json").write_text(
    json.dumps(resolved_response) + "\n",
    encoding="utf-8",
)

action_level_response = deepcopy(resolved_response)
action_level_result = action_level_response["EvaluationResults"][0]
resource_level_result = action_level_result.pop("ResourceSpecificResults")[0]
action_level_result["MatchedStatements"] = resource_level_result["MatchedStatements"]
(root / "response-action-level.json").write_text(
    json.dumps(action_level_response) + "\n",
    encoding="utf-8",
)

action_level_decision_mutant = deepcopy(action_level_response)
action_level_decision_mutant["EvaluationResults"][0]["EvalDecision"] = "implicitDeny"
(root / "response-action-level-decision-mutant.json").write_text(
    json.dumps(action_level_decision_mutant) + "\n",
    encoding="utf-8",
)

action_level_attribution_mutant = deepcopy(action_level_response)
action_level_attribution_mutant["EvaluationResults"][0]["MatchedStatements"] = []
(root / "response-action-level-attribution-mutant.json").write_text(
    json.dumps(action_level_attribution_mutant) + "\n",
    encoding="utf-8",
)

no_resource_dir = root / "no-resource-vectors"
no_resource_dir.mkdir()
no_resource_vector = deepcopy(ambiguous_vector)
no_resource_vector["resource_arns"] = []
(no_resource_dir / "no-resource.json").write_text(
    json.dumps(no_resource_vector, indent=2) + "\n",
    encoding="utf-8",
)

missing_concrete_arn = deepcopy(position_response(position(38), position(271)))
missing_concrete_arn["EvaluationResults"][0]["ResourceSpecificResults"][0][
    "EvalResourceName"
] = "arn:aws:s3:::orbit-infra-79s5rw-tfstate/different/x"
(root / "response-missing-concrete-arn.json").write_text(
    json.dumps(missing_concrete_arn) + "\n",
    encoding="utf-8",
)

authorization_source = (
    taxonomy_path.parent
    / "vectors"
    / "aws_iam_policy.deployer_data__EnvDataBucketLifecycle__ALL_none_matching.json"
)
authorization_split_dir = root / "authorization-split-vectors"
authorization_split_dir.mkdir()
authorization_split_vector = json.loads(authorization_source.read_text(encoding="utf-8"))
authorization_split_vector["expect"]["matched_sid_required"] = []
(authorization_split_dir / "authorization-split.json").write_text(
    json.dumps(authorization_split_vector, indent=2) + "\n",
    encoding="utf-8",
)
authorization_aliases = {
    "s3:DeleteBucketOwnershipControls",
    "s3:DeleteBucketPublicAccessBlock",
}
rendered_authorization_resources = [
    resource.replace("${SUFFIX}", "79s5rw")
    for resource in authorization_split_vector["resource_arns"]
]
authorization_actions = sorted(authorization_split_vector["action_names"])
authorization_direct = [
    action for action in authorization_actions if action not in authorization_aliases
]
authorization_aliased = [
    action for action in authorization_actions if action in authorization_aliases
]
(root / "expected-authorization-split-inputs.json").write_text(
    json.dumps(
        {
            "actions": authorization_actions,
            "resources": sorted(rendered_authorization_resources),
            "accepted_action_groups": [
                authorization_actions,
                authorization_direct,
                authorization_aliased,
            ],
            "required_action_groups": [authorization_direct, authorization_aliased],
        },
        sort_keys=True,
    ) + "\n",
    encoding="utf-8",
)

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

duplicate_resource = "arn:aws:secretsmanager:us-east-1:000000000000:secret:duplicate"
duplicate_response = {
    "EvaluationResults": [{
        "EvalActionName": "secretsmanager:CreateSecret",
        "EvalResourceName": duplicate_resource,
        "EvalDecision": "allowed",
        "ResourceSpecificResults": [{
            "EvalResourceName": duplicate_resource,
            "EvalResourceDecision": "allowed",
            "MatchedStatements": [],
            "MissingContextValues": [],
        }],
    }],
}
(root / "response-duplicate.json").write_text(
    json.dumps(duplicate_response) + "\n",
    encoding="utf-8",
)
(root / "response-empty.json").write_text("{}\n", encoding="utf-8")

isolated_dir = root / "isolated-vectors"
isolated_dir.mkdir()
isolated = json.loads((taxonomy_path.parent / "valid-custom-isolated.json").read_text(encoding="utf-8"))
isolated["expect"]["matched_sid_forbidden"] = ["LogsCreateWithTag"]
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
isolated_position_mutant = deepcopy(isolated_response)
isolated_position_mutant["EvaluationResults"][0]["ResourceSpecificResults"][0][
    "MatchedStatements"
] = [match(38, end_column=271)]
(root / "response-isolated-position-mutant.json").write_text(
    json.dumps(isolated_position_mutant) + "\n",
    encoding="utf-8",
)

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
        "simulation_mode": "custom",
        "assertion_kind": "decision",
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

isolated_role_vector = json.loads(
    (taxonomy_path.parent / "valid-custom-isolated.json").read_text(encoding="utf-8")
)
(role_dir / "role-isolated.json").write_text(
    json.dumps(isolated_role_vector, indent=2) + "\n",
    encoding="utf-8",
)

custom_records = []
for vector in role_vectors:
    policy = policy_for(vector["document"])
    custom_records.append({
        "case_id": vector["case_id"],
        "decision_observed": "allowed",
        "matched_sids": [],
        "expect": vector["expect"],
        "pass": True,
        "mode": "custom",
        "document_hashes_submitted": {
            "policy_input_list": [{"sha256": hashlib.sha256(policy.encode("utf-8")).hexdigest()}],
            "permissions_boundary_policy_input_list": [],
        },
    })
custom_records.append({
    "case_id": isolated_role_vector["case_id"],
    "decision_observed": isolated_role_vector["expect"]["decision"],
    "matched_sids": [],
    "expect": isolated_role_vector["expect"],
    "pass": True,
    "mode": "custom-isolated",
    "document_hashes_submitted": {
        "policy_input_list": [],
        "permissions_boundary_policy_input_list": [],
    },
})
(root / "role-custom-report.json").write_text(
    json.dumps({"records": custom_records, "summary": {"total": 4, "passed": 4, "failed": 0, "runner_failures": 0}}, indent=2) + "\n",
    encoding="utf-8",
)


def write_single_custom_report(name, vector_path, policy):
    vector = json.loads(vector_path.read_text(encoding="utf-8"))
    record = {
        "case_id": vector["case_id"],
        "decision_observed": vector["expect"]["decision"],
        "matched_sids": vector["expect"]["matched_sid_required"],
        "expect": vector["expect"],
        "pass": True,
        "mode": "custom",
        "document_hashes_submitted": {
            "policy_input_list": [{
                "sha256": hashlib.sha256(policy.encode("utf-8")).hexdigest(),
            }],
            "permissions_boundary_policy_input_list": [],
        },
    }
    (root / f"role-{name}-custom-report.json").write_text(
        json.dumps({
            "records": [record],
            "summary": {
                "total": 1,
                "passed": 1,
                "failed": 0,
                "runner_failures": 0,
            },
        }, indent=2) + "\n",
        encoding="utf-8",
    )


write_single_custom_report(
    "deployer-position",
    deployer_position_dir / "position.json",
    real_deployer_policy,
)
for name, _, _, _ in scanner_vectors:
    write_single_custom_report(
        f"scanner-{name}",
        root / f"scanner-{name}-vectors" / "position.json",
        scanner_position_policy,
    )

role_action_level_dir = root / "role-action-level-vectors"
role_action_level_dir.mkdir()
role_action_level_vector = deepcopy(role_vectors[0])
role_action_level_vector["resource_arns"] = ["*"]
(role_action_level_dir / "action-level.json").write_text(
    json.dumps(role_action_level_vector, indent=2) + "\n",
    encoding="utf-8",
)
write_single_custom_report(
    "action-level",
    role_action_level_dir / "action-level.json",
    policy_for(role_action_level_vector["document"]),
)
(root / "response-role-action-level.json").write_text(
    json.dumps({
        "EvaluationResults": [{
            "EvalActionName": "iam:GetRole",
            "EvalResourceName": "*",
            "EvalDecision": "allowed",
            "MatchedStatements": [],
            "MissingContextValues": [],
        }],
    }) + "\n",
    encoding="utf-8",
)

divergence_custom_records = deepcopy(custom_records)
divergence_custom_records[0]["decision_observed"] = "implicitDeny"
divergence_custom_records[0]["matched_sids"] = ["CustomMatchedSid"]
divergence_custom_records[0]["pass"] = False
(root / "role-divergence-custom-report.json").write_text(
    json.dumps({
        "records": divergence_custom_records,
        "summary": {"total": 4, "passed": 3, "failed": 1, "runner_failures": 0},
    }, indent=2) + "\n",
    encoding="utf-8",
)
(root / "role-missing-custom-report.json").write_text(
    json.dumps({
        "records": custom_records[1:],
        "summary": {"total": 3, "passed": 3, "failed": 0, "runner_failures": 0},
    }, indent=2) + "\n",
    encoding="utf-8",
)

role_projection_plan = json.loads(role_projection_plan_source.read_text(encoding="utf-8"))
(root / "role-projection-plan.json").write_text(
    json.dumps(role_projection_plan, indent=2) + "\n",
    encoding="utf-8",
)
role_projection_resources = {
    resource["address"]: resource["values"]["policy"]
    for resource in role_projection_plan["planned_values"]["root_module"]["resources"]
    if isinstance(resource.get("values"), dict)
    and isinstance(resource["values"].get("policy"), str)
}
role_projection_documents = [
    "aws_iam_role_policy.plan_reader_deny",
    "aws_iam_role_policy.plan_reader_state",
    "aws_iam_policy.deployer_data",
    "aws_iam_policy.deployer_ec2",
    "aws_iam_policy.deployer_elb_ecs",
    "aws_iam_policy.deployer_guard",
    "aws_iam_policy.deployer_iam",
    "aws_iam_policy.deployer_state",
    "aws_iam_role_policy.publisher",
]
projection_vector_dir = root / "role-projection-vectors"
projection_vector_dir.mkdir()
projection_records = []
for index, document in enumerate(role_projection_documents):
    category = next(
        entry
        for entry in categories
        if entry["document"] == document and entry["category"] == "simulator-decision"
    )
    vector = {
        "schema_version": 1,
        "case_id": category["case_id"],
        "document": document,
        "sid": category["sid"],
        "simulation_mode": "custom",
        "assertion_kind": "decision",
        "action_names": ["iam:GetRole"],
        "resource_arns": [
            f"arn:aws:iam::${{ACCOUNT_ID}}:role/orbit-infra-${{SUFFIX}}-projection-{index}"
        ],
        "context_entries": [],
        "expect": {
            "decision": "allowed",
            "matched_sid_required": [],
            "matched_sid_forbidden": [],
        },
    }
    (projection_vector_dir / f"projection-{index}.json").write_text(
        json.dumps(vector, indent=2) + "\n",
        encoding="utf-8",
    )
    projection_records.append({
        "case_id": vector["case_id"],
        "decision_observed": "allowed",
        "matched_sids": [],
        "expect": vector["expect"],
        "pass": True,
        "mode": "custom",
        "document_hashes_submitted": {
            "policy_input_list": [{
                "sha256": hashlib.sha256(
                    role_projection_resources[document].encode("utf-8")
                ).hexdigest()
            }],
            "permissions_boundary_policy_input_list": [],
        },
    })
(root / "role-projection-custom-report.json").write_text(
    json.dumps({
        "records": projection_records,
        "summary": {
            "total": len(projection_records),
            "passed": len(projection_records),
            "failed": 0,
            "runner_failures": 0,
        },
    }, indent=2) + "\n",
    encoding="utf-8",
)

wrong_hash_payload = {
    "records": deepcopy(projection_records),
    "summary": {
        "total": len(projection_records),
        "passed": len(projection_records),
        "failed": 0,
        "runner_failures": 0,
    },
}
wrong_hash_case_id = next(
    vector["case_id"]
    for vector in (
        json.loads(path.read_text(encoding="utf-8"))
        for path in projection_vector_dir.glob("*.json")
    )
    if vector["document"] == "aws_iam_policy.deployer_guard"
)
wrong_hash_record = next(
    record
    for record in wrong_hash_payload["records"]
    if record["case_id"] == wrong_hash_case_id
)
wrong_hash_record["document_hashes_submitted"]["policy_input_list"][0]["sha256"] = "0" * 64
(root / "role-projection-wrong-hash-custom-report.json").write_text(
    json.dumps(wrong_hash_payload, indent=2) + "\n",
    encoding="utf-8",
)
wrong_mode_payload = {
    "records": deepcopy(projection_records),
    "summary": wrong_hash_payload["summary"],
}
wrong_mode_record = next(
    record for record in wrong_mode_payload["records"]
    if record["case_id"] == wrong_hash_case_id
)
wrong_mode_record["mode"] = "principal"
(root / "role-projection-wrong-mode-custom-report.json").write_text(
    json.dumps(wrong_mode_payload, indent=2) + "\n",
    encoding="utf-8",
)

duplicate_sid_plan = deepcopy(role_projection_plan)
for address in (
    "aws_iam_role_policy.plan_reader_deny",
    "aws_iam_role_policy.plan_reader_state",
):
    resource = next(
        item
        for item in duplicate_sid_plan["planned_values"]["root_module"]["resources"]
        if item["address"] == address
    )
    policy = json.loads(resource["values"]["policy"])
    policy["Statement"][0]["Sid"] = "CrossDocumentDuplicate"
    resource["values"]["policy"] = json.dumps(policy, separators=(",", ":"))
(root / "role-duplicate-sid-plan.json").write_text(
    json.dumps(duplicate_sid_plan, indent=2) + "\n",
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
args = sys.argv[3:]
record_path.write_text(json.dumps(args) + "\n", encoding="utf-8")
if args[:2] != ["iam", "simulate-custom-policy"] or not sys.argv[2]:
    raise SystemExit(0)

expected_path = Path(sys.argv[2])
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
    accepted = expected.get("accepted_action_groups") if key == "actions" else None
    valid = sorted(submitted) in accepted if accepted is not None else sorted(submitted) == expected[key]
    if not valid:
        want = json.dumps(accepted if accepted is not None else expected[key], separators=(",", ":"))
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
    if [ "${FAKE_AWS_SCENARIO:-success}" = authorization-split ]; then
      python3 - "$@" <<'PY'
import json
import sys


args = sys.argv[1:]


def option_values(option):
    index = args.index(option) + 1
    values = []
    while index < len(args) and not args[index].startswith("--"):
        values.append(args[index])
        index += 1
    return values


actions = option_values("--action-names")
resources = option_values("--resource-arns")
aliases = {
    "s3:DeleteBucketOwnershipControls",
    "s3:DeleteBucketPublicAccessBlock",
}
direct = sorted(action for action in actions if action not in aliases)
aliased = sorted(action for action in actions if action in aliases)
if direct and aliased:
    print(
        "An error occurred (InvalidInput) when calling the "
        "SimulateCustomPolicy operation: Invalid Input Actions: "
        f"[{','.join(direct)}] and [{','.join(aliased)}] "
        "require different authorization information.",
        file=sys.stderr,
    )
    raise SystemExit(254)
response = {
    "EvaluationResults": [
        {
            "EvalActionName": action,
            "EvalDecision": "allowed",
            "MatchedStatements": [],
            "ResourceSpecificResults": [
                {
                    "EvalResourceName": resource,
                    "EvalResourceDecision": "allowed",
                    "MatchedStatements": [],
                    "MissingContextValues": [],
                }
                for resource in resources
            ],
        }
        for action in actions
    ]
}
print(json.dumps(response, separators=(",", ":")))
PY
      exit 0
    fi
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
    if [ "${FAKE_AWS_SCENARIO:-}" = create-midway ] && \
       [ "$create_count" -eq "${FAKE_ROLE_FAILURE_CREATE_INDEX:-2}" ]; then
      echo 'An error occurred (ServiceFailure) when calling the CreateRole operation' >&2
      exit 254
    fi
    tags_json="$(python3 - "$@" <<'PY'
import json
import sys

args = sys.argv[1:]
index = args.index("--tags") + 1
tags = []
while index < len(args) and not args[index].startswith("--"):
    key_part, separator, value_part = args[index].partition(",Value=")
    if not separator or not key_part.startswith("Key="):
        raise SystemExit(f"FAIL: fake create-role received an invalid tag: {args[index]}")
    tags.append({"Key": key_part.removeprefix("Key="), "Value": value_part})
    index += 1
print(json.dumps(tags, separators=(",", ":")))
PY
)"
    jq -cn --argjson tags "$tags_json" '{tags:$tags,policy:false}' >"$FAKE_ROLE_STATE_DIR/$role_name.json"
    if [ "${FAKE_AWS_SCENARIO:-}" = nonce-tamper ] && \
       [ -n "${FAKE_ROLE_INJECTION_SUFFIX:-}" ] && \
       [[ "$role_name" == *"$FAKE_ROLE_INJECTION_SUFFIX" ]]; then
      jq '
        if any(.tags[]; .Key == "OrbitIamSimulationNonce") then
          .tags |= map(
            if .Key == "OrbitIamSimulationNonce" then
              .Value = (if .Value == "00000000000000000000000000000000" then
                "11111111111111111111111111111111"
              else
                "00000000000000000000000000000000"
              end)
            else . end
          )
        else
          .tags += [{Key:"OrbitIamSimulationNonce",Value:"00000000000000000000000000000000"}]
        end
      ' "$FAKE_ROLE_STATE_DIR/$role_name.json" >"$FAKE_ROLE_STATE_DIR/$role_name.json.next"
      mv "$FAKE_ROLE_STATE_DIR/$role_name.json.next" "$FAKE_ROLE_STATE_DIR/$role_name.json"
    fi
    jq -cn --arg role "$role_name" '{Role:{RoleName:$role}}'
    if [ "${FAKE_AWS_SCENARIO:-}" = term-during-create ] && \
       [ "$create_count" -eq "${FAKE_ROLE_FAILURE_CREATE_INDEX:-1}" ]; then
      kill -TERM "$IAM_SIM_LANE_PID"
    fi
    ;;
  "iam list-role-tags")
    role_name="$(value_after --role-name "$@")"
    [ -f "$FAKE_ROLE_STATE_DIR/$role_name.json" ] || {
      echo 'An error occurred (NoSuchEntity) when calling the ListRoleTags operation' >&2
      exit 254
    }
    tags_json="$(jq -c '.tags' "$FAKE_ROLE_STATE_DIR/$role_name.json")"
    if [ "${FAKE_AWS_SCENARIO:-}" = tag-mismatch ]; then
      tags_json="$(jq -c '
        map(if .Key == "OrbitIamSimulationRun" then .Value = "wrong-run" else . end)
      ' <<<"$tags_json")"
    fi
    jq -cn --argjson tags "$tags_json" '{Tags:$tags}'
    ;;
  "iam put-role-policy")
    role_name="$(value_after --role-name "$@")"
    if [ "${FAKE_AWS_SCENARIO:-}" = put-policy-fails ] && \
       [ -n "${FAKE_ROLE_INJECTION_SUFFIX:-}" ] && \
       [[ "$role_name" == *"$FAKE_ROLE_INJECTION_SUFFIX" ]]; then
      echo 'An error occurred (ServiceFailure) when calling the PutRolePolicy operation' >&2
      exit 254
    fi
    jq '.policy = true' "$FAKE_ROLE_STATE_DIR/$role_name.json" >"$FAKE_ROLE_STATE_DIR/$role_name.json.next"
    mv "$FAKE_ROLE_STATE_DIR/$role_name.json.next" "$FAKE_ROLE_STATE_DIR/$role_name.json"
    printf '{}\n'
    if [ "${FAKE_AWS_SCENARIO:-}" = term-during-put ] && \
       [ -n "${FAKE_ROLE_INJECTION_SUFFIX:-}" ] && \
       [[ "$role_name" == *"$FAKE_ROLE_INJECTION_SUFFIX" ]]; then
      kill -TERM "$IAM_SIM_LANE_PID"
    fi
    ;;
  "iam simulate-principal-policy")
    if [ -n "${FAKE_PRINCIPAL_RESPONSE:-}" ]; then
      cat "$FAKE_PRINCIPAL_RESPONSE"
      exit 0
    fi
    action="$(value_after --action-names "$@")"
    resource="$(value_after --resource-arns "$@")"
    decision=allowed
    matched='[]'
    if [ "${FAKE_AWS_SCENARIO:-success}" = organizations-difference ] && \
       ! value_after --policy-exclusion-list "$@" >/dev/null 2>&1; then
      decision=explicitDeny
      matched='[{"SourcePolicyId":"OrganizationsPolicy","SourcePolicyType":"Organizations Policy"}]'
    fi
    jq -cn --arg action "$action" --arg resource "$resource" \
      --arg decision "$decision" --argjson matched "$matched" \
      '{EvaluationResults:[{EvalActionName:$action,EvalResourceName:$resource,EvalDecision:$decision,ResourceSpecificResults:[{EvalResourceName:$resource,EvalResourceDecision:$decision,MatchedStatements:$matched,MissingContextValues:[]}]}]}'
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
    if ! jq -e '.policy == true' "$FAKE_ROLE_STATE_DIR/$role_name.json" >/dev/null; then
      echo 'An error occurred (NoSuchEntity) when calling the DeleteRolePolicy operation' >&2
      exit 254
    fi
    jq '.policy = false' "$FAKE_ROLE_STATE_DIR/$role_name.json" >"$FAKE_ROLE_STATE_DIR/$role_name.json.next"
    mv "$FAKE_ROLE_STATE_DIR/$role_name.json.next" "$FAKE_ROLE_STATE_DIR/$role_name.json"
    printf '{}\n'
    if [ "${FAKE_AWS_SCENARIO:-}" = term-after-delete-policy ] && \
       [ -n "${FAKE_ROLE_INJECTION_SUFFIX:-}" ] && \
       [[ "$role_name" == *"$FAKE_ROLE_INJECTION_SUFFIX" ]]; then
      kill -TERM "$IAM_SIM_LANE_PID"
    fi
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

assert_submitted_document_equals_plan() {
  local plan=$1
  local calls=$2
  local address=$3
  local option=$4
  python3 - "$plan" "$calls" "$address" "$option" <<'PY'
import json
from pathlib import Path
import sys

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
call_paths = sorted(Path(sys.argv[2]).glob("*.json"))
address = sys.argv[3]
option = sys.argv[4]
resources = plan["planned_values"]["root_module"]["resources"]
matches = [resource for resource in resources if resource.get("address") == address]
if len(matches) != 1:
    raise SystemExit(f"FAIL: comparison plan has {len(matches)} resources for {address}")
expected = matches[0]["values"]["policy"]
simulate_calls = []
for path in call_paths:
    args = json.loads(path.read_text(encoding="utf-8"))
    if args[:2] == ["iam", "simulate-custom-policy"]:
        simulate_calls.append(args)
if len(simulate_calls) != 1:
    raise SystemExit(f"FAIL: comparison found {len(simulate_calls)} simulator calls")
args = simulate_calls[0]
if args.count(option) != 1:
    raise SystemExit(f"FAIL: comparison requires exactly one {option}")
index = args.index(option) + 1
submitted = []
while index < len(args) and not args[index].startswith("--"):
    submitted.append(args[index])
    index += 1
if submitted != [expected]:
    raise SystemExit(f"FAIL: submitted {option} document differs from plan text for {address}")
PY
}

mutate_submitted_document() {
  local calls=$1
  local option=$2
  python3 - "$calls" "$option" <<'PY'
import json
from pathlib import Path
import sys

option = sys.argv[2]
for path in sorted(Path(sys.argv[1]).glob("*.json")):
    args = json.loads(path.read_text(encoding="utf-8"))
    if args[:2] != ["iam", "simulate-custom-policy"]:
        continue
    index = args.index(option) + 1
    args[index] += " "
    path.write_text(json.dumps(args) + "\n", encoding="utf-8")
    break
else:
    raise SystemExit("FAIL: no simulator call to mutate")
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
  env -u AWS_PROFILE \
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
    "$IAM_SIM_RUNNER" --plan "${IAM_SIM_TEST_PLAN:-$phase2_plan}" \
      --vectors "$vectors" --report "$report" "$@"
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

run_real_vector_runner() {
  local vectors=$1
  local report=$2
  local plan="${IAM_SIM_CONTRACT_PLAN:-$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json}"
  env -u AWS_PROFILE -u AWS_ENDPOINT_URL \
    AWS_CLI_BIN="$phase2_fake_aws" \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
    FAKE_AWS_CALL_DIR="$phase2_calls" \
    FAKE_ROLE_STATE_DIR="$phase2_roles" \
    FAKE_AWS_SCENARIO=success \
    FAKE_AWS_RESPONSE="$phase2_dir/response-empty.json" \
    FAKE_AWS_EXPECTED_INPUTS= \
    IAM_SIM_RETRY_BASE_SECONDS=0 \
    TARGET=aws \
    "$IAM_SIM_RUNNER" --plan "$plan" --vectors "$vectors" --report "$report"
}

validate_real_report() {
  local vectors=$1
  local report=$2
  python3 - "$vectors" "$report" <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys


def fail(message):
    raise SystemExit(f"FAIL: {message}")


vector_dir = Path(sys.argv[1])
report_path = Path(sys.argv[2])
try:
    expected = [
        json.loads(path.read_text(encoding="utf-8"))["case_id"]
        for path in sorted(vector_dir.rglob("*.json"))
    ]
    payload = json.loads(report_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError, KeyError) as exc:
    fail(f"cannot read real-vector report inputs: {exc}")
if len(expected) != 239:
    fail(f"real vector set has {len(expected)} case ids, expected 239")
records = payload.get("records") if isinstance(payload, dict) else None
if not isinstance(records, list):
    fail("report records must be an array")
case_ids = [record.get("case_id") for record in records if isinstance(record, dict)]
if len(case_ids) != len(records) or any(not isinstance(case_id, str) for case_id in case_ids):
    fail("every report record must have a string case_id")
counts = Counter(case_ids)
repeated = sorted(case_id for case_id, count in counts.items() if count != 1)
if repeated:
    fail(f"report repeats selected case_id: {repeated[0]}")
missing = sorted(set(expected) - set(case_ids))
if missing:
    fail(f"report omits selected case_id: {missing[0]}")
unexpected = sorted(set(case_ids) - set(expected))
if unexpected:
    fail(f"report contains unselected case_id: {unexpected[0]}")
if payload.get("summary", {}).get("total") != 239:
    fail("report summary total must equal 239")

by_id = {record["case_id"]: record for record in records}
shared_groups = set()
shared_cases = set()
for case_id, record in by_id.items():
    peers = record.get("shared_call_case_ids")
    if not isinstance(peers, list) or any(not isinstance(peer, str) for peer in peers):
        fail(f"shared_call_case_ids must be a string array: {case_id}")
    if len(peers) != len(set(peers)) or case_id in peers:
        fail(f"shared_call_case_ids is not a unique peer set: {case_id}")
    if not peers:
        continue
    group = tuple(sorted([case_id, *peers]))
    shared_groups.add(group)
    shared_cases.update(group)
    for peer in peers:
        peer_record = by_id.get(peer)
        if peer_record is None:
            fail(f"shared-call peer is absent from report: {peer}")
        reciprocal = tuple(sorted([peer, *peer_record.get("shared_call_case_ids", [])]))
        if reciprocal != group:
            fail(f"shared-call peers are not reciprocal: {case_id} and {peer}")
if len(shared_groups) != 8 or len(shared_cases) != 16:
    fail(
        "shared-call census differs: "
        f"{len(shared_groups)} batches and {len(shared_cases)} cases"
    )
print(
    "PASS: real 239-vector report coverage "
    "(239 records, 8 shared-call batches, 16 shared cases)"
)
PY
}

mutate_shared_core_overlap() {
  local destination=$1
  python3 - "$IAM_SIM_CORE" "$destination" <<'PY_MUTATE_SHARED_CORE_OVERLAP'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
overlap_line = "            if start < end and start < span_end and span_start < end:"
strict_line = (
    "            if span_start <= start < span_end "
    "and span_start <= end < span_end:"
)
if source.count(overlap_line) != 1:
    raise SystemExit("FAIL: shared-core unique-overlap mutation anchor changed")
Path(sys.argv[2]).write_text(source.replace(overlap_line, strict_line), encoding="utf-8")
PY_MUTATE_SHARED_CORE_OVERLAP
}

mutate_shared_core_scanner() {
  local destination=$1
  local name=$2
  python3 - "$IAM_SIM_CORE" "$destination" "$name" <<'PY_MUTATE_SHARED_CORE_SCANNER'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
scan_line = "                        statement, end = decoder.raw_decode(policy, start)"
if source.count(scan_line) != 1:
    raise SystemExit("FAIL: shared-core scanner mutation anchor changed")
if sys.argv[3] == "string-delimiters":
    mutation = (
        '                        end = policy.index("}", start) + 1\n'
        "                        statement = json.loads(policy[start:end])"
    )
else:
    mutation = (
        "                        mutated_policy = policy[:start] + "
        "policy[start:].replace(chr(92) + chr(34), chr(34), 1)\n"
        "                        statement, end = decoder.raw_decode(mutated_policy, start)"
    )
Path(sys.argv[2]).write_text(source.replace(scan_line, mutation), encoding="utf-8")
PY_MUTATE_SHARED_CORE_SCANNER
}

run_iam_simulate_runner_contracts() {
  local census disagreement_vectors expected_inputs isolated_policy output real_rc report report_mutant
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

    for name in real-position multiline-position; do
      reset_phase2_fake
      report="$phase2_dir/$name-report.json"
      if output="$(IAM_SIM_TEST_PLAN="$phase2_dir/plan-$name.json" \
        run_phase2_runner success "$phase2_dir/response-$name.json" \
          "$phase2_dir/$name-vectors" "$report" 2>&1)" && \
         jq -e '
           .records | length == 1
           and .[0].matched_sids == ["DenyReadStateObjectsOutsideScope"]
           and .[0].pass == true
         ' "$report" >/dev/null; then
        pass_case "runner maps $name exact statement span"
      else
        fail_case "runner maps $name exact statement span" "$output"
      fi
    done

    for name in string-delimiters escaped-quotes; do
      reset_phase2_fake
      report="$phase2_dir/scanner-$name-report.json"
      if output="$(IAM_SIM_TEST_PLAN="$phase2_dir/plan-scanner-position.json" \
        run_phase2_runner success "$phase2_dir/response-scanner-$name.json" \
          "$phase2_dir/scanner-$name-vectors" "$report" 2>&1)" && \
         jq -e '.records | length == 1 and .[0].pass == true' \
           "$report" >/dev/null; then
        pass_case "runner scans exact statement spans with $name"
      else
        fail_case "runner scans exact statement spans with $name" "$output"
      fi
    done

    reset_phase2_fake
    report="$phase2_dir/deployer-position-report.json"
    if output="$(IAM_SIM_TEST_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      run_phase2_runner success "$phase2_dir/response-deployer-position.json" \
        "$phase2_dir/deployer-position-vectors" "$report" 2>&1)" && \
       jq -e '
         .records | length == 1
         and .[0].matched_sids == ["ClickhouseSecretCreateWithTag"]
         and .[0].pass == true
       ' "$report" >/dev/null; then
      pass_case "runner maps real deployer_data delimiter-inclusive range"
    else
      fail_case "runner maps real deployer_data delimiter-inclusive range" "$output"
    fi
    IAM_SIM_TEST_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      expect_runner_failure "runner real deployer_data two-statement overlap refusal" \
        "ambiguous matched statement position from PolicyInputList.1: overlap_count=2 document_length=5682 statement_span_count=18 returned_range=[1777,2054) first_span=[14,112):EcrVerificationAuth last_span=[4809,5657):EnvDataBucketLifecycle" \
        success "$phase2_dir/response-deployer-ambiguous.json" \
        "$phase2_dir/deployer-position-vectors"

    reset_phase2_fake
    report="$phase2_dir/resolved-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-resolved.json" \
      "$phase2_dir/ambiguous-vectors" "$report" 2>&1)" && \
       assert_submitted_document_equals_plan "$phase2_plan" "$phase2_calls" \
         "aws_iam_policy.task_boundary" "--policy-input-list" && \
       assert_submitted_document_equals_plan "$phase2_plan" "$phase2_calls" \
         "aws_iam_policy.task_boundary" "--permissions-boundary-policy-input-list"; then
      pass_case "runner resolves policy and boundary bytes from plan addresses"
    else
      fail_case "runner resolves policy and boundary bytes from plan addresses" "$output"
    fi
    if mutate_submitted_document "$phase2_calls" "--policy-input-list"; then
      expect_failure "runner plan policy byte equality" \
        "submitted --policy-input-list document differs from plan text" \
        assert_submitted_document_equals_plan "$phase2_plan" "$phase2_calls" \
          "aws_iam_policy.task_boundary" "--policy-input-list"
    else
      fail_case "runner plan policy byte equality mutation setup" "no simulator call"
    fi
    if mutate_submitted_document "$phase2_calls" \
      "--permissions-boundary-policy-input-list"; then
      expect_failure "runner boundary policy byte equality" \
        "submitted --permissions-boundary-policy-input-list document differs from plan text" \
        assert_submitted_document_equals_plan "$phase2_plan" "$phase2_calls" \
          "aws_iam_policy.task_boundary" "--permissions-boundary-policy-input-list"
    else
      fail_case "runner boundary policy byte equality mutation setup" "no simulator call"
    fi

    reset_phase2_fake
    report="$phase2_dir/action-level-star-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-action-level.json" \
      "$phase2_dir/ambiguous-vectors" "$report" 2>&1)" && \
       jq -e '
         .records | length == 1
         and .[0].decision_observed == "allowed"
         and .[0].matched_sids == ["EcrAuth"]
         and .[0].pass == true
       ' "$report" >/dev/null; then
      pass_case "runner uses action-level decision and attribution for explicit star"
    else
      fail_case "runner uses action-level decision and attribution for explicit star" "$output"
    fi
    expect_runner_failure "runner action-level explicit-star decision" \
      "decision mismatch for ecr:GetAuthorizationToken *: expected allowed, observed implicitDeny" \
      success "$phase2_dir/response-action-level-decision-mutant.json" \
      "$phase2_dir/ambiguous-vectors"

    reset_phase2_fake
    report="$phase2_dir/action-level-no-resource-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-action-level.json" \
      "$phase2_dir/no-resource-vectors" "$report" 2>&1)" && \
       jq -e '
         .records | length == 1
         and .[0].decision_observed == "allowed"
         and .[0].matched_sids == ["EcrAuth"]
         and .[0].pass == true
       ' "$report" >/dev/null && \
       jq -e 'index("--resource-arns") == null' "$phase2_calls/1.json" >/dev/null; then
      pass_case "runner uses action-level decision and attribution with no submitted resource"
    else
      fail_case "runner uses action-level decision and attribution with no submitted resource" "$output"
    fi
    expect_runner_failure "runner action-level no-resource attribution" \
      "required matched Sid is absent: EcrAuth" \
      success "$phase2_dir/response-action-level-attribution-mutant.json" \
      "$phase2_dir/no-resource-vectors"

    expect_runner_failure "runner multiple-concrete action-level refusal" \
      "action-level result lacks ResourceSpecificResults for s3:GetObject" \
      success "$phase2_dir/response-multiple-concrete-action-level.json" \
      "$phase2_dir/runner-vectors"
    IAM_SIM_TEST_PLAN="$phase2_dir/plan-real-position.json" \
      expect_runner_failure "runner missing exact concrete ARN refusal" \
        "submitted resource ARN is absent from response: s3:GetObject arn:aws:s3:::orbit-infra-79s5rw-tfstate/other/x" \
        success "$phase2_dir/response-missing-concrete-arn.json" \
        "$phase2_dir/real-position-vectors"

    IAM_SIM_TEST_PLAN="$phase2_dir/plan-missing-document.json" \
      expect_runner_failure "runner missing named document" \
        "named policy document is absent from plan: aws_iam_policy.task_boundary" \
        success "$phase2_dir/response-resolved.json" "$phase2_dir/ambiguous-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 0 ]; then
      fail_case "runner missing named document" "fake AWS was called"
    fi
    IAM_SIM_TEST_PLAN="$phase2_dir/plan-missing-sid.json" \
      expect_runner_failure "runner missing named Sid" \
        "named Sid is absent from plan policy aws_iam_policy.deployer_data: LogsCreateWithTag" \
        success "$phase2_dir/response-isolated.json" "$phase2_dir/isolated-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 0 ]; then
      fail_case "runner missing named Sid" "fake AWS was called"
    fi
    IAM_SIM_TEST_PLAN="$phase2_dir/plan-duplicate-sid.json" \
      expect_runner_failure "runner duplicate named Sid" \
        "named Sid matches more than one statement in plan policy aws_iam_policy.deployer_data: LogsCreateWithTag" \
        success "$phase2_dir/response-isolated.json" "$phase2_dir/isolated-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 0 ]; then
      fail_case "runner duplicate named Sid" "fake AWS was called"
    fi

    expect_runner_failure "runner ambiguous position refusal" "ambiguous matched statement position" \
      success "$phase2_dir/response-ambiguous.json" "$phase2_dir/ambiguous-vectors"
    expect_runner_failure "runner unmapped position refusal" \
      "unmapped matched statement position from PolicyInputList.1: unmapped_offset=0 document_length=288 statement_span_count=2 returned_range=[0,1) first_span=[37,152):FixtureAllow last_span=[153,286):DenyReadStateObjectsOutsideScope" \
      success "$phase2_dir/response-unmapped.json" "$phase2_dir/runner-vectors"
    expect_runner_failure "runner unknown source-label refusal" \
      "unrecognised SourcePolicyId UnknownPolicyLabel; submitted labels: PolicyInputList.1" \
      success "$phase2_dir/response-unknown-source.json" "$phase2_dir/runner-vectors"
    expect_runner_failure "runner missing submitted ARN refusal" "submitted resource ARN is absent" \
      success "$phase2_dir/response-missing-arn.json" "$phase2_dir/runner-vectors"

    reset_phase2_fake
    report="$phase2_dir/shared-call-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-duplicate.json" \
      "$phase2_dir/duplicate-vectors" "$report" 2>&1)" && \
       [ "$(phase2_call_count iam simulate-custom-policy)" -eq 1 ] && \
       jq -e '
         .records | length == 2
         and .[0].decision_observed == "allowed"
         and .[1].decision_observed == "allowed"
         and .[0].matched_sids == []
         and .[1].matched_sids == []
         and .[0].shared_call_case_ids == [.[1].case_id]
         and .[1].shared_call_case_ids == [.[0].case_id]
         and all(.[]; .pass == true)
       ' "$report" >/dev/null; then
      pass_case "runner emits one observed record per compatible shared-call case"
    else
      fail_case "runner emits one observed record per compatible shared-call case" "$output"
    fi

    reset_phase2_fake
    report="$phase2_dir/authorization-split-report.json"
    expected_inputs="$phase2_dir/expected-authorization-split-inputs.json"
    if output="$(env -u AWS_PROFILE \
      PATH="$phase2_dir/bin:$PATH" \
      AWS_CLI_BIN=aws \
      AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
      FAKE_AWS_CALL_DIR="$phase2_calls" \
      FAKE_ROLE_STATE_DIR="$phase2_roles" \
      FAKE_AWS_SCENARIO=authorization-split \
      FAKE_AWS_RESPONSE="$phase2_dir/response-empty.json" \
      FAKE_AWS_EXPECTED_INPUTS="$expected_inputs" \
      IAM_SIM_RETRY_BASE_SECONDS=0 \
      TARGET=aws \
      "$IAM_SIM_RUNNER" --plan "$phase2_plan" \
        --vectors "$phase2_dir/authorization-split-vectors" \
        --report "$report" 2>&1)" && \
       python3 - "$phase2_calls" "$expected_inputs" <<'PY' &&
import json
from pathlib import Path
import sys


calls = []
for path in sorted(Path(sys.argv[1]).glob("*.json")):
    args = json.loads(path.read_text(encoding="utf-8"))
    if args[:2] != ["iam", "simulate-custom-policy"]:
        continue
    index = args.index("--action-names") + 1
    actions = []
    while index < len(args) and not args[index].startswith("--"):
        actions.append(args[index])
        index += 1
    calls.append(sorted(actions))
expected = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if sorted(calls) != sorted(expected["required_action_groups"]):
    raise SystemExit(
        f"FAIL: authorization action groups differ: {json.dumps(calls)}"
    )
PY
       jq -e '
         .summary == {"failed":0,"passed":1,"runner_failures":0,"total":1}
         and .records[0].decision_observed == "allowed"
         and .records[0].matched_sids == []
         and .records[0].pass == true
       ' "$report" >/dev/null; then
      pass_case "runner splits S3 operations that require different authorization information"
    else
      fail_case "runner splits S3 operations that require different authorization information" "$output"
    fi

    reset_phase2_fake
    report="$phase2_dir/real-vector-report.json"
    set +e
    # shellcheck disable=SC2153 # VECTORS is provided by the sourcing suite.
    output="$(run_real_vector_runner "$VECTORS" "$report" 2>&1)"
    real_rc=$?
    set -e
    if [ "$real_rc" -ne 0 ] && \
       grep -Fq 'AWS simulator response lacks EvaluationResults array' <<<"$output" && \
       [ "$(phase2_call_count iam simulate-custom-policy)" -eq 231 ] && \
       census="$(validate_real_report "$VECTORS" "$report" 2>&1)"; then
      pass_case "real-vector batch safety and report completeness -> $census"
    else
      fail_case "real-vector batch safety and report completeness" \
        "rc=$real_rc calls=$(phase2_call_count iam simulate-custom-policy) output=$output"
    fi

    report_mutant="$phase2_dir/real-vector-report-dropped-shared-case.json"
    python3 - "$report" "$report_mutant" <<'PY'
import json
from pathlib import Path
import sys

source = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for index, record in enumerate(source["records"]):
    if record.get("shared_call_case_ids"):
        del source["records"][index]
        break
else:
    raise SystemExit("FAIL: report mutation found no shared-call case")
source["summary"]["total"] = len(source["records"])
Path(sys.argv[2]).write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")
PY
    expect_failure "real report dropped shared case" "report omits selected case_id" \
      validate_real_report "$VECTORS" "$report_mutant"

    disagreement_vectors="$phase2_dir/real-disagreement-vectors"
    cp -R "$VECTORS" "$disagreement_vectors"
    python3 - "$disagreement_vectors/aws_iam_policy.deployer_iam__DenyRoleMutationMissingBoundary__ALL_none_protected-resource.json" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
vector = json.loads(path.read_text(encoding="utf-8"))
vector["expect"]["decision"] = "implicitDeny"
path.write_text(json.dumps(vector, indent=2) + "\n", encoding="utf-8")
PY
    IAM_SIM_TEST_PLAN="${IAM_SIM_CONTRACT_PLAN:-$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json}" \
      expect_runner_failure "real colliding-case expectation disagreement" \
        "expectation-disagreeing duplicate action/resource pair in batch" \
        success "$phase2_dir/response-empty.json" "$disagreement_vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 0 ]; then
      fail_case "real colliding-case expectation disagreement" "fake AWS was called"
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
    expect_runner_failure "runner isolated wrapper position attribution" \
      "forbidden matched Sid is present: LogsCreateWithTag" \
      success "$phase2_dir/response-isolated-position-mutant.json" \
        "$phase2_dir/isolated-vectors"

    core_mutant="$phase2_dir/iam-simulate-core-strict-containment.py"
    mutate_shared_core_overlap "$core_mutant"
    for name in two-statement real-deployer; do
      reset_phase2_fake
      if [ "$name" = two-statement ]; then
        mutant_plan="$phase2_plan"
        mutant_response="$phase2_dir/response-baseline.json"
        mutant_vectors="$phase2_dir/runner-vectors"
      else
        mutant_plan="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json"
        mutant_response="$phase2_dir/response-deployer-position.json"
        mutant_vectors="$phase2_dir/deployer-position-vectors"
      fi
      set +e
      output="$(IAM_SIM_CORE="$core_mutant" IAM_SIM_TEST_PLAN="$mutant_plan" \
        run_phase2_runner success "$mutant_response" "$mutant_vectors" \
          "$phase2_dir/strict-$name-report.json" 2>&1)"
      mutant_rc=$?
      set -e
      if [ "$mutant_rc" -ne 0 ] && \
         grep -Fq 'FAIL: unmapped matched statement position from PolicyInputList.1' \
           <<<"$output"; then
        pass_case "runner $name shared-core unique-overlap mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
      else
        fail_case "runner $name shared-core unique-overlap mutation did not fail as required" \
          "rc=$mutant_rc output=$output"
      fi
    done

    for name in string-delimiters escaped-quotes; do
      core_mutant="$phase2_dir/iam-simulate-core-$name-mutant.py"
      mutate_shared_core_scanner "$core_mutant" "$name"
      reset_phase2_fake
      set +e
      output="$(IAM_SIM_CORE="$core_mutant" \
        IAM_SIM_TEST_PLAN="$phase2_dir/plan-scanner-position.json" \
        run_phase2_runner success "$phase2_dir/response-scanner-$name.json" \
          "$phase2_dir/scanner-$name-vectors" \
          "$phase2_dir/$name-mutant-report.json" 2>&1)"
      mutant_rc=$?
      set -e
      if [ "$mutant_rc" -ne 0 ] && grep -Fq 'FAIL: cannot scan submitted statement:' \
        <<<"$output"; then
        pass_case "runner $name shared-core scanner mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
      else
        fail_case "runner $name shared-core scanner mutation did not fail as required" \
          "rc=$mutant_rc output=$output"
      fi
    done

    reset_phase2_fake
    report="$phase2_dir/shared-core-restored-report.json"
    if output="$(IAM_SIM_TEST_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      run_phase2_runner success "$phase2_dir/response-deployer-position.json" \
        "$phase2_dir/deployer-position-vectors" "$report" 2>&1)" && \
       jq -e '.records | length == 1 and .[0].pass == true' "$report" >/dev/null; then
      pass_case "runner shared-core mutations restored PASS"
    else
      fail_case "runner shared-core mutation restoration" "$output"
    fi

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
  local test_account="${IAM_SIM_TEST_ACCOUNT_ID:-000000000000}"
  local test_plan="${IAM_SIM_TEST_ROLE_PLAN:-$phase2_plan}"
  local test_vectors="${IAM_SIM_TEST_ROLE_VECTORS:-$phase2_dir/role-vectors}"
  local test_report="${IAM_SIM_TEST_ROLE_REPORT:-$phase2_dir/role-report.json}"
  local test_custom_report="${IAM_SIM_TEST_ROLE_CUSTOM_REPORT:-$phase2_dir/role-custom-report.json}"
  local test_role_lane="${IAM_SIM_TEST_ROLE_LANE:-$IAM_SIM_ROLE_LANE}"
  local test_run_id="${IAM_SIM_TEST_RUN_ID:-fixture-run}"
  shift
  env -u AWS_PROFILE \
    PATH="$phase2_dir/bin:$PATH" \
    AWS_CLI_BIN=aws \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
    FAKE_AWS_CALL_DIR="$phase2_calls" \
    FAKE_ROLE_STATE_DIR="$phase2_roles" \
    FAKE_AWS_SCENARIO="$scenario" \
    FAKE_PRINCIPAL_RESPONSE="${IAM_SIM_TEST_PRINCIPAL_RESPONSE:-}" \
    FAKE_ACCOUNT_ID="$test_account" \
    FAKE_ROLE_FAILURE_CREATE_INDEX="${IAM_SIM_TEST_ROLE_FAILURE_CREATE_INDEX:-}" \
    FAKE_ROLE_INJECTION_SUFFIX="${IAM_SIM_TEST_ROLE_INJECTION_SUFFIX:-}" \
    IAM_SIM_RUN_ID="$test_run_id" \
    TARGET=aws \
    "$test_role_lane" --plan "$test_plan" --vectors "$test_vectors" \
      --report "$test_report" --expect-account "$test_account" \
      --custom-report "$test_custom_report" "$@"
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


validate_role_account_redaction() {
  local report=$1
  local calls=$2
  local account=$3
  python3 - "$report" "$calls" "$account" <<'PY_VALIDATE_ROLE_ACCOUNT_REDACTION'
import json
from pathlib import Path
import re
import sys

report_path = Path(sys.argv[1])
call_paths = sorted(Path(sys.argv[2]).glob("*.json"), key=lambda path: int(path.stem))
account = sys.argv[3]
placeholder = "000000000000"
serialized = report_path.read_text(encoding="utf-8")
without_hashes = re.sub(
    r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{64}(?![0-9A-Fa-f])",
    "",
    serialized,
)
account_runs = set(re.findall(r"(?<![0-9])[0-9]{12}(?![0-9])", without_hashes))
unexpected = sorted(account_runs - {placeholder})
if unexpected:
    raise SystemExit(f"FAIL: role report contains unredacted 12-digit account id: {unexpected[0]}")
payload = json.loads(serialized)
if payload.get("account") != placeholder or payload.get("account_redacted") is not True:
    raise SystemExit("FAIL: role report lacks the placeholder account and account_redacted marker")
if payload.get("ownership_nonce") != "<redacted>" or payload.get("ownership_nonce_redacted") is not True:
    raise SystemExit("FAIL: role report lacks the redacted ownership nonce marker")
if not payload.get("manual_cleanup"):
    raise SystemExit("FAIL: role report account-redaction fixture lacks a manual-cleanup note")

calls = [json.loads(path.read_text(encoding="utf-8")) for path in call_paths]
creates = [call for call in calls if call[:2] == ["iam", "create-role"]]
simulations = [call for call in calls if call[:2] == ["iam", "simulate-principal-policy"]]
if not creates or not simulations:
    raise SystemExit("FAIL: role account-redaction fixture lacks live-call records")
for call in creates:
    role_name = call[call.index("--role-name") + 1]
    trust_policy = call[call.index("--assume-role-policy-document") + 1]
    expected_trust = f"arn:aws:iam::{account}:root"
    if account not in role_name or json.loads(trust_policy)["Statement"][0]["Principal"]["AWS"] != expected_trust:
        raise SystemExit("FAIL: create-role call did not retain the real account id")
    tag_index = call.index("--tags") + 1
    nonce_tag = next(
        (tag for tag in call[tag_index:] if tag.startswith("Key=OrbitIamSimulationNonce,Value=")),
        None,
    )
    if nonce_tag is None:
        raise SystemExit("FAIL: create-role call lacks the ownership nonce")
    nonce = nonce_tag.partition(",Value=")[2]
    if nonce in serialized:
        raise SystemExit("FAIL: role report contains an ownership nonce")
for call in simulations:
    source_arn = call[call.index("--policy-source-arn") + 1]
    if not source_arn.startswith(f"arn:aws:iam::{account}:role/") or account not in source_arn:
        raise SystemExit("FAIL: simulate-principal-policy call did not retain the real account id")
PY_VALIDATE_ROLE_ACCOUNT_REDACTION
}

validate_role_creation_failure() {
  local report=$1
  local calls=$2
  local expected_role_count=$3
  local failure_index=$4
  local created_count=$5
  python3 - "$report" "$calls" "$expected_role_count" "$failure_index" "$created_count" <<'PY_VALIDATE_ROLE_CREATION_FAILURE'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
call_paths = sorted(Path(sys.argv[2]).glob("*.json"), key=lambda path: int(path.stem))
calls = [json.loads(path.read_text(encoding="utf-8")) for path in call_paths]
expected_role_count = int(sys.argv[3])
failure_index = int(sys.argv[4])
created_count = int(sys.argv[5])
roles = payload.get("projection", {}).get("roles", [])
if len(roles) != expected_role_count:
    raise SystemExit(
        f"FAIL: role failure fixture requires {expected_role_count} projections, found {len(roles)}"
    )
if not 1 <= created_count <= failure_index <= expected_role_count:
    raise SystemExit("FAIL: role failure fixture has invalid creation boundaries")
if expected_role_count == 8:
    failed_role = roles[failure_index - 1]
    if failed_role.get("role_kind") != "deployer" or not failed_role.get("name", "").endswith("-deployer-p4"):
        raise SystemExit("FAIL: eight-role failure must be injected at deployer p4")

role_names = [role["name"] for role in roles]


def operation_calls(operation):
    return [call for call in calls if call[:2] == ["iam", operation]]


def call_role_name(call):
    return call[call.index("--role-name") + 1]


creates = [call_role_name(call) for call in operation_calls("create-role")]
deletes = [call_role_name(call) for call in operation_calls("delete-role")]
gets = [call_role_name(call) for call in operation_calls("get-role")]
if creates != role_names[:failure_index]:
    raise SystemExit("FAIL: role failure fixture created a role after the injected failure")
if deletes != list(reversed(role_names[:created_count])):
    raise SystemExit("FAIL: role failure cleanup did not delete every created role in reverse order")
if gets != role_names[:failure_index]:
    raise SystemExit("FAIL: role failure cleanup did not verify every attempted role absent")
later_roles = set(role_names[failure_index:])
for call in calls:
    if "--role-name" in call and call_role_name(call) in later_roles:
        raise SystemExit("FAIL: role failure fixture touched a role after the injected failure")
PY_VALIDATE_ROLE_CREATION_FAILURE
}

run_role_creation_failure_case() {
  local label=$1
  local scenario=$2
  local expected=$3
  local expected_role_count=$4
  local failure_index=$5
  local created_count=$6
  local test_plan=$7
  local test_vectors=$8
  local test_custom_report=$9
  local test_role_lane=${10:-$IAM_SIM_ROLE_LANE}
  local report="$phase2_dir/role-failure-$scenario-$expected_role_count-$failure_index.json"
  local output rc fail_line
  reset_phase2_fake
  set +e
  output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    IAM_SIM_TEST_ROLE_PLAN="$test_plan" \
    IAM_SIM_TEST_ROLE_VECTORS="$test_vectors" \
    IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$test_custom_report" \
    IAM_SIM_TEST_ROLE_REPORT="$report" \
    IAM_SIM_TEST_ROLE_FAILURE_CREATE_INDEX="$failure_index" \
    IAM_SIM_TEST_ROLE_LANE="$test_role_lane" \
    run_phase2_role_lane "$scenario" 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && [ -n "$fail_line" ] && grep -Fq "$expected" <<<"$output" && \
     validate_role_creation_failure \
       "$report" "$phase2_calls" "$expected_role_count" "$failure_index" "$created_count" && \
     ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
    pass_case "$label -> $fail_line"
  else
    fail_case "$label" "rc=$rc output=$output"
  fi
}


role_wrong_hash_expected_line() {
  local plan=$1
  local vectors=$2
  local custom_report=$3
  python3 - "$plan" "$vectors" "$custom_report" <<'PY_ROLE_WRONG_HASH_EXPECTED'
import hashlib
import json
from pathlib import Path
import sys

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
vectors = [
    json.loads(path.read_text(encoding="utf-8"))
    for path in Path(sys.argv[2]).glob("*.json")
]
report = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
policies = {
    resource["address"]: resource["values"]["policy"]
    for resource in plan["planned_values"]["root_module"]["resources"]
    if isinstance(resource.get("values"), dict)
    and isinstance(resource["values"].get("policy"), str)
}
for vector in vectors:
    record = next(item for item in report["records"] if item["case_id"] == vector["case_id"])
    observed = record["document_hashes_submitted"]["policy_input_list"][0]["sha256"]
    expected = hashlib.sha256(policies[vector["document"]].encode("utf-8")).hexdigest()
    if observed != expected:
        print(
            f"FAIL: custom report policy hash mismatch for {vector['case_id']}: "
            f"report={observed} plan={expected}"
        )
        break
else:
    raise SystemExit("FAIL: wrong-hash fixture contains no mismatch")
PY_ROLE_WRONG_HASH_EXPECTED
}

validate_role_cleanup_race() {
  local report=$1
  local calls=$2
  local role_state=$3
  local scenario=$4
  python3 - "$report" "$calls" "$role_state" "$scenario" <<'PY_VALIDATE_ROLE_CLEANUP_RACE'
import json
from pathlib import Path
import sys

report_path = Path(sys.argv[1])
call_paths = sorted(Path(sys.argv[2]).glob("*.json"), key=lambda path: int(path.stem))
role_state = Path(sys.argv[3])
scenario = sys.argv[4]
if not report_path.is_file():
    raise SystemExit("FAIL: cleanup race did not write its report")
payload = json.loads(report_path.read_text(encoding="utf-8"))
roles = payload.get("projection", {}).get("roles", [])
if len(roles) != 8:
    raise SystemExit(f"FAIL: cleanup race requires eight roles, found {len(roles)}")
role_names = [role["name"] for role in roles]
target = next(
    (role["name"] for role in roles if role.get("name", "").endswith("-deployer-p4")),
    None,
)
if target is None:
    raise SystemExit("FAIL: cleanup race lacks the deployer-p4 injection role")
calls = [json.loads(path.read_text(encoding="utf-8")) for path in call_paths]


def operation_names(operation):
    return [
        call[call.index("--role-name") + 1]
        for call in calls
        if call[:2] == ["iam", operation]
    ]


puts = operation_names("put-role-policy")
delete_policies = operation_names("delete-role-policy")
delete_roles = operation_names("delete-role")
gets = operation_names("get-role")
if scenario in {"term-during-put", "put-policy-fails"}:
    expected_puts = role_names[:5]
    expected_delete_policies = list(reversed(role_names[:5]))
    expected_records = 0
    if puts != expected_puts or puts[-1] != target:
        raise SystemExit("FAIL: cleanup race was not injected while loading deployer-p4")
elif scenario == "term-after-delete-policy":
    expected_puts = role_names
    expected_delete_policies = list(reversed(role_names))
    expected_records = 9
    if target not in delete_policies:
        raise SystemExit("FAIL: cleanup race was not injected after deployer-p4 policy deletion")
else:
    raise SystemExit(f"FAIL: unknown cleanup-race scenario: {scenario}")
if delete_policies != expected_delete_policies:
    raise SystemExit("FAIL: cleanup race did not attempt every marked policy in reverse order")
if delete_roles != list(reversed(role_names)):
    raise SystemExit("FAIL: cleanup race did not delete every role in reverse order")
if gets != role_names:
    raise SystemExit("FAIL: cleanup race did not verify NoSuchEntity for every role")
if any(role_state.glob("*.json")):
    raise SystemExit("FAIL: cleanup race left role state behind")
if len(payload.get("records", [])) != expected_records:
    raise SystemExit("FAIL: cleanup race report has the wrong completed-record count")
PY_VALIDATE_ROLE_CLEANUP_RACE
}

run_role_cleanup_race_case() {
  local label=$1
  local scenario=$2
  local expected_rc=$3
  local expected_failure=$4
  local report="$phase2_dir/role-$scenario-report.json"
  local output rc fail_line
  reset_phase2_fake
  set +e
  output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
    IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
    IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
    IAM_SIM_TEST_ROLE_REPORT="$report" \
    IAM_SIM_TEST_ROLE_INJECTION_SUFFIX=-deployer-p4 \
    run_phase2_role_lane "$scenario" 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -eq "$expected_rc" ] && [ -n "$fail_line" ] && \
     grep -Fq "$expected_failure" <<<"$output" && \
     validate_role_cleanup_race "$report" "$phase2_calls" "$phase2_roles" "$scenario"; then
    pass_case "$label mutation -> $fail_line"
  else
    fail_case "$label mutation did not fail safely" "rc=$rc output=$output"
  fi
}

run_role_projection_restored_case() {
  local label=$1
  local report="$phase2_dir/role-${label// /-}-report.json"
  local output
  reset_phase2_fake
  if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
    IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
    IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
    IAM_SIM_TEST_ROLE_REPORT="$report" \
    run_phase2_role_lane success 2>&1)" && \
     [ "$(phase2_call_count iam create-role)" -eq 8 ] && \
     [ "$(phase2_call_count iam delete-role)" -eq 8 ] && \
     [ "$(phase2_call_count iam get-role)" -eq 8 ] && \
     ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
    pass_case "$label restored PASS"
  else
    fail_case "$label restoration" "$output"
  fi
}

validate_role_nonce_tamper() {
  local report=$1
  local calls=$2
  local role_state=$3
  python3 - "$report" "$calls" "$role_state" <<'PY_VALIDATE_ROLE_NONCE_TAMPER'
import json
from pathlib import Path
import re
import sys

report_path = Path(sys.argv[1])
call_paths = sorted(Path(sys.argv[2]).glob("*.json"), key=lambda path: int(path.stem))
role_state = Path(sys.argv[3])
calls = [json.loads(path.read_text(encoding="utf-8")) for path in call_paths]
puts = sum(call[:2] == ["iam", "put-role-policy"] for call in calls)
delete_policies = sum(call[:2] == ["iam", "delete-role-policy"] for call in calls)
delete_roles = sum(call[:2] == ["iam", "delete-role"] for call in calls)
if puts or delete_policies or delete_roles:
    raise SystemExit(
        "FAIL: nonce tamper reached policy or role mutations: "
        f"put={puts} delete-policy={delete_policies} delete-role={delete_roles}"
    )
creates = [call for call in calls if call[:2] == ["iam", "create-role"]]
if len(creates) != 8:
    raise SystemExit(f"FAIL: nonce tamper requires eight create calls, found {len(creates)}")
nonces = set()
for call in creates:
    index = call.index("--tags") + 1
    raw_tags = []
    while index < len(call) and not call[index].startswith("--"):
        raw_tags.append(call[index])
        index += 1
    tags = {}
    for raw_tag in raw_tags:
        key_part, separator, value = raw_tag.partition(",Value=")
        if not separator or not key_part.startswith("Key="):
            raise SystemExit("FAIL: nonce tamper create call has an invalid tag")
        tags[key_part.removeprefix("Key=")] = value
    if set(tags) != {"OrbitIamSimulationRun", "OrbitIamSimulationNonce"}:
        raise SystemExit("FAIL: nonce tamper create call lacks both ownership tags")
    nonce = tags["OrbitIamSimulationNonce"]
    if re.fullmatch(r"[0-9a-f]{32}", nonce) is None:
        raise SystemExit("FAIL: ownership nonce is not 32 lowercase hex characters")
    nonces.add(nonce)
if len(nonces) != 1:
    raise SystemExit("FAIL: one invocation did not use one ownership nonce")
state_paths = list(role_state.glob("*.json"))
if len(state_paths) != 8:
    raise SystemExit("FAIL: nonce tamper refusal did not preserve all eight roles for manual cleanup")
target_path = next(
    (path for path in state_paths if path.stem.endswith("-deployer-p4")),
    None,
)
if target_path is None:
    raise SystemExit("FAIL: nonce tamper state lacks deployer-p4")
target_tags = {
    tag["Key"]: tag["Value"]
    for tag in json.loads(target_path.read_text(encoding="utf-8"))["tags"]
}
if target_tags.get("OrbitIamSimulationRun") != "fixture-run":
    raise SystemExit("FAIL: nonce tamper changed the run-id tag")
if target_tags.get("OrbitIamSimulationNonce") in nonces:
    raise SystemExit("FAIL: nonce tamper did not change deployer-p4's nonce")
if not report_path.is_file():
    raise SystemExit("FAIL: nonce tamper did not write its report")
serialized = report_path.read_text(encoding="utf-8")
for nonce in nonces | {target_tags.get("OrbitIamSimulationNonce")}:
    if nonce and nonce in serialized:
        raise SystemExit("FAIL: role report contains an ownership nonce")
payload = json.loads(serialized)
if not any("ownership tag mismatch" in note for note in payload.get("manual_cleanup", [])):
    raise SystemExit("FAIL: nonce tamper report does not name the ownership mismatch")
PY_VALIDATE_ROLE_NONCE_TAMPER
}

mutate_role_report_redaction() {
  local source_path=$1
  local destination=$2
  python3 - "$source_path" "$destination" "$REPO_ROOT" <<'PY_MUTATE_ROLE_REPORT_REDACTION'
from pathlib import Path
import shlex
import sys

source_path = Path(sys.argv[1])
destination = Path(sys.argv[2])
source = source_path.read_text(encoding="utf-8")
root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
redaction_block = (
    'payload = redact_sensitive(payload, [\n'
    '    (role_plan["account_id"], "000000000000"),\n'
    '    (nonce, "<redacted>"),\n'
    '])\n'
)
if source.count(root_line) != 1 or source.count(redaction_block) != 1:
    raise SystemExit("FAIL: role report-redaction mutation anchor changed")
source = source.replace(root_line, f"REPO_ROOT={shlex.quote(sys.argv[3])}")
source = source.replace(redaction_block, "")
destination.write_text(source, encoding="utf-8")
PY_MUTATE_ROLE_REPORT_REDACTION
  chmod +x "$destination"
}

mutate_role_nonce_check() {
  local source_path=$1
  local destination=$2
  python3 - "$source_path" "$destination" "$REPO_ROOT" <<'PY_MUTATE_ROLE_NONCE_CHECK'
from pathlib import Path
import shlex
import sys

source_path = Path(sys.argv[1])
destination = Path(sys.argv[2])
source = source_path.read_text(encoding="utf-8")
root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
complete_check = '[{Key:$run_key,Value:$run_value},{Key:$nonce_key,Value:$nonce_value}]'
run_only_check = '[{Key:$run_key,Value:$run_value}]'
if source.count(root_line) != 1 or source.count(complete_check) != 1:
    raise SystemExit("FAIL: role nonce-check mutation anchor changed")
source = source.replace(root_line, f"REPO_ROOT={shlex.quote(sys.argv[3])}")
source = source.replace(complete_check, run_only_check)
destination.write_text(source, encoding="utf-8")
PY_MUTATE_ROLE_NONCE_CHECK
  chmod +x "$destination"
}

mutate_role_cleanup_high_indices() {
  local source_path=$1
  local destination=$2
  python3 - "$source_path" "$destination" "$REPO_ROOT" <<'PY_MUTATE_ROLE_CLEANUP_HIGH_INDICES'
from pathlib import Path
import shlex
import sys

source_path = Path(sys.argv[1])
destination = Path(sys.argv[2])
source = source_path.read_text(encoding="utf-8")
root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
cleanup_loop = (
    '  for ((index = role_count - 1; index >= 0; index--)); do\n'
    '    role_name="$(jq -r ".roles[$index].name" "$role_plan")"\n'
)
mutated_loop = (
    '  for ((index = role_count > 3 ? 2 : role_count - 1; index >= 0; index--)); do\n'
    '    role_name="$(jq -r ".roles[$index].name" "$role_plan")"\n'
)
if source.count(root_line) != 1 or source.count(cleanup_loop) != 1:
    raise SystemExit("FAIL: role high-index cleanup mutation anchor changed")
source = source.replace(root_line, f"REPO_ROOT={shlex.quote(sys.argv[3])}")
source = source.replace(cleanup_loop, mutated_loop)
destination.write_text(source, encoding="utf-8")
PY_MUTATE_ROLE_CLEANUP_HIGH_INDICES
  chmod +x "$destination"
}
validate_role_selection_report() {
  local report=$1
  python3 - "$report" <<'PY_VALIDATE_ROLE_SELECTION'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
records = payload.get("records", [])
exclusions = payload.get("exclusions", [])
summary = payload.get("summary", {})
reason = "isolated single-statement simulation has no principal equivalent"
if len(records) != 3:
    raise SystemExit(f"FAIL: role selection requires three custom-vector records, found {len(records)}")
if any(record.get("mode") != "principal" for record in records):
    raise SystemExit("FAIL: role selection did not execute every custom vector through principal simulation")
isolated = [entry for entry in exclusions if entry.get("reason") == reason]
if len(isolated) != 1 or not isolated[0].get("case_id"):
    raise SystemExit("FAIL: role selection must record one custom-isolated exclusion with its reason")
if summary.get("cases_selected") != 3:
    raise SystemExit("FAIL: role selection summary must count three selected cases")
if summary.get("cases_excluded_by_reason", {}).get(reason) != 1:
    raise SystemExit("FAIL: role selection summary must count the custom-isolated exclusion reason")
PY_VALIDATE_ROLE_SELECTION
}

mutate_role_selection_report() {
  local source=$1
  local destination=$2
  python3 - "$source" "$destination" <<'PY_MUTATE_ROLE_SELECTION'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
reason = "isolated single-statement simulation has no principal equivalent"
entry = next(item for item in payload["exclusions"] if item.get("reason") == reason)
entry["reason"] = "mutated generic exclusion"
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY_MUTATE_ROLE_SELECTION
}

validate_role_projection_report() {
  local report=$1
  local vectors=$2
  local plan=$3
  local calls=$4
  python3 - "$report" "$vectors" "$plan" "$calls" <<'PY_VALIDATE_ROLE_PROJECTION'
import hashlib
import json
from pathlib import Path
import re
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
vectors = {
    vector["case_id"]: vector
    for path in Path(sys.argv[2]).glob("*.json")
    for vector in [json.loads(path.read_text(encoding="utf-8"))]
}
plan = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
policies = {
    resource["address"]: resource["values"]["policy"]
    for resource in plan["planned_values"]["root_module"]["resources"]
    if isinstance(resource.get("values"), dict)
    and isinstance(resource["values"].get("policy"), str)
}
roles = payload.get("projection", {}).get("roles", [])
if len(roles) != 8:
    raise SystemExit(f"FAIL: role projection requires eight passes, found {len(roles)}")
by_kind = {}
for role in roles:
    by_kind.setdefault(role.get("role_kind"), []).append(role)
plan_reader_documents = [
    "aws_iam_role_policy.plan_reader_deny",
    "aws_iam_role_policy.plan_reader_state",
]
deployer_documents = [
    "aws_iam_policy.deployer_data",
    "aws_iam_policy.deployer_ec2",
    "aws_iam_policy.deployer_elb_ecs",
    "aws_iam_policy.deployer_guard",
    "aws_iam_policy.deployer_iam",
    "aws_iam_policy.deployer_state",
]
publisher_documents = ["aws_iam_role_policy.publisher"]
for kind, documents in (
    ("plan-reader", plan_reader_documents),
    ("publisher", publisher_documents),
):
    projections = by_kind.get(kind, [])
    if len(projections) != 1 or projections[0].get("projection_kind") != "combined":
        raise SystemExit(f"FAIL: role projection requires one combined {kind} pass")
    addresses = [entry.get("address") for entry in projections[0].get("source_documents", [])]
    if addresses != documents:
        raise SystemExit(f"FAIL: role projection {kind} source order is {addresses}")
deployer = by_kind.get("deployer", [])
if len(deployer) != 6:
    raise SystemExit(
        f"FAIL: role projection requires six deployer per-document passes, found {len(deployer)}"
    )
actual_deployer_documents = []
for projection in deployer:
    if projection.get("projection_kind") != "per-document":
        raise SystemExit("FAIL: role projection deployer pass is not per-document")
    sources = projection.get("source_documents", [])
    if len(sources) != 1 or not sources[0].get("sha256"):
        raise SystemExit("FAIL: role projection deployer pass lacks one addressed source hash")
    actual_deployer_documents.append(sources[0].get("address"))
if actual_deployer_documents != deployer_documents:
    raise SystemExit(
        f"FAIL: role projection deployer source order is {actual_deployer_documents}"
    )
for projection in roles:
    source_entries = projection.get("source_documents", [])
    source_addresses = [entry.get("address") for entry in source_entries]
    expected_statements = []
    for address in source_addresses:
        policy = policies[address]
        expected_hash = hashlib.sha256(policy.encode("utf-8")).hexdigest()
        entry = next(item for item in source_entries if item.get("address") == address)
        if entry.get("sha256") != expected_hash:
            raise SystemExit(f"FAIL: role projection source hash differs for {address}")
        statements = json.loads(policy)["Statement"]
        expected_statements.extend(statements if isinstance(statements, list) else [statements])
    projected_policy = projection.get("policy_document")
    if json.loads(projected_policy).get("Statement") != expected_statements:
        raise SystemExit(
            f"FAIL: role projection did not concatenate statements in source order: {projection.get('projection_id')}"
        )
    expected_source_size = sum(
        len(re.sub(r"\s", "", policies[address])) for address in source_addresses
    )
    if projection.get("source_character_count") != expected_source_size:
        raise SystemExit(
            f"FAIL: role projection source-character measurement differs: {projection.get('projection_id')}"
        )
    if projection.get("policy_character_count") != len(re.sub(r"\s", "", projected_policy)):
        raise SystemExit(
            f"FAIL: role projection policy-character measurement differs: {projection.get('projection_id')}"
        )
records = payload.get("records", [])
if len(records) != len(vectors):
    raise SystemExit(
        f"FAIL: role projection requires {len(vectors)} case records, found {len(records)}"
    )
for record in records:
    case_id = record.get("case_id")
    projection = record.get("projection", {})
    source_entries = projection.get("source_documents", [])
    source_addresses = [entry.get("address") for entry in source_entries]
    if vectors[case_id]["document"] not in source_addresses:
        raise SystemExit(f"FAIL: role projection record does not identify its deciding pass: {case_id}")
    if not projection.get("projection_id") or not projection.get("policy_sha256"):
        raise SystemExit(f"FAIL: role projection record lacks projection identity and hash: {case_id}")
if payload.get("summary", {}).get("cases_selected") != len(vectors):
    raise SystemExit("FAIL: role projection summary selected count is wrong")

call_paths = sorted(Path(sys.argv[4]).glob("*.json"), key=lambda path: int(path.stem))
calls = [json.loads(path.read_text(encoding="utf-8")) for path in call_paths]
role_names = [role["name"] for role in roles]

def operation_calls(operation):
    return [call for call in calls if call[:2] == ["iam", operation]]

def call_role_name(call):
    return call[call.index("--role-name") + 1]

creates = [call_role_name(call) for call in operation_calls("create-role")]
puts = [call_role_name(call) for call in operation_calls("put-role-policy")]
delete_policies = [call_role_name(call) for call in operation_calls("delete-role-policy")]
delete_roles = [call_role_name(call) for call in operation_calls("delete-role")]
gets = [call_role_name(call) for call in operation_calls("get-role")]
if creates != role_names or puts != role_names:
    raise SystemExit("FAIL: role projection did not create and load every pass in order")
if delete_policies != list(reversed(role_names)) or delete_roles != list(reversed(role_names)):
    raise SystemExit("FAIL: role projection did not delete every pass in reverse order")
if gets != role_names:
    raise SystemExit("FAIL: role projection did not verify NoSuchEntity for every pass")
last_create_index = max(calls.index(call) for call in operation_calls("create-role"))
first_put_index = min(calls.index(call) for call in operation_calls("put-role-policy"))
preflight_tag_reads = [
    call_role_name(call)
    for call in calls[last_create_index + 1:first_put_index]
    if call[:2] == ["iam", "list-role-tags"]
]
if preflight_tag_reads != role_names:
    raise SystemExit("FAIL: role projection lacks a complete ownership preflight before policy loads")
for operation in ("delete-role-policy", "delete-role"):
    for call in operation_calls(operation):
        index = calls.index(call)
        name = call_role_name(call)
        previous = calls[index - 1]
        if previous[:2] != ["iam", "list-role-tags"] or call_role_name(previous) != name:
            raise SystemExit(
                f"FAIL: role projection {operation} lacks an immediate ownership tag re-read for {name}"
            )
PY_VALIDATE_ROLE_PROJECTION
}

mutate_role_projection_report() {
  local source=$1
  local destination=$2
  python3 - "$source" "$destination" <<'PY_MUTATE_ROLE_PROJECTION'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
roles = payload["projection"]["roles"]
index = next(
    index
    for index, role in enumerate(roles)
    if role.get("role_kind") == "deployer"
)
roles.pop(index)
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY_MUTATE_ROLE_PROJECTION
}

validate_role_divergence_report() {
  local report=$1
  python3 - "$report" <<'PY_VALIDATE_ROLE_DIVERGENCE'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
summary = payload.get("summary", {})
if summary.get("agreements") != 2 or summary.get("divergences") != 1:
    raise SystemExit("FAIL: role divergence summary must contain two agreements and one divergence")
divergences = [record for record in payload.get("records", []) if record.get("comparison") == "divergence"]
if len(divergences) != 1:
    raise SystemExit("FAIL: role divergence report must preserve one divergence record")
record = divergences[0]
evidence = record.get("divergence", {})
if record.get("pass") is not True:
    raise SystemExit("FAIL: role divergence must not mark the case or run failed")
if evidence.get("observed_in") != ["scp-excluded", "default"]:
    raise SystemExit("FAIL: role divergence must identify both principal runs")
if evidence.get("custom_lane") != {
    "decision_observed": "implicitDeny",
    "matched_sids": ["CustomMatchedSid"],
}:
    raise SystemExit("FAIL: role divergence lost the custom-lane decision or matched Sids")
for run in ("scp_excluded", "default"):
    if evidence.get(run) != {"decision_observed": "allowed", "matched_sids": []}:
        raise SystemExit(f"FAIL: role divergence lost the {run} decision or matched Sids")
projection = record.get("projection", {})
if not projection.get("projection_id") or not projection.get("source_documents"):
    raise SystemExit("FAIL: role divergence does not identify its deciding projection")
PY_VALIDATE_ROLE_DIVERGENCE
}

mutate_role_divergence_report() {
  local source=$1
  local destination=$2
  python3 - "$source" "$destination" <<'PY_MUTATE_ROLE_DIVERGENCE'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
record = next(item for item in payload["records"] if item.get("comparison") == "divergence")
record["comparison"] = "agreement"
record.pop("divergence")
payload["summary"]["agreements"] += 1
payload["summary"]["divergences"] -= 1
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY_MUTATE_ROLE_DIVERGENCE
}

validate_role_two_runs() {
  local calls=$1
  local report=$2
  python3 - "$calls" "$report" <<'PY_VALIDATE_ROLE_TWO_RUNS'
import json
from pathlib import Path
import sys

call_paths = sorted(Path(sys.argv[1]).glob("*.json"), key=lambda path: int(path.stem))
calls = [json.loads(path.read_text(encoding="utf-8")) for path in call_paths]
simulations = [args for args in calls if args[:2] == ["iam", "simulate-principal-policy"]]
payload = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
records = payload.get("records", [])
if len(simulations) != 2 * len(records):
    raise SystemExit("FAIL: two-run contract requires exactly two simulations per selected case")
exclusion = '{"PolicyType":"scp"}'
for index in range(0, len(simulations), 2):
    excluded = simulations[index]
    default = simulations[index + 1]
    if excluded.count("--policy-exclusion-list") != 1:
        raise SystemExit(
            "FAIL: two-run contract requires one exact scp-excluded call and one default call per case"
        )
    option_index = excluded.index("--policy-exclusion-list")
    if excluded[option_index + 1] != exclusion or "--policy-exclusion-list" in default:
        raise SystemExit(
            "FAIL: two-run contract requires one exact scp-excluded call and one default call per case"
        )
    if excluded[:option_index] + excluded[option_index + 2:] != default:
        raise SystemExit("FAIL: two-run contract changed inputs other than the SCP exclusion")
for record in records:
    if record.get("comparison") != "agreement":
        raise SystemExit("FAIL: two-run contract did not compare the scp-excluded run to custom")
    if record.get("scp_excluded", {}).get("decision_observed") != "allowed" or \
       record.get("default", {}).get("decision_observed") != "explicitDeny":
        raise SystemExit("FAIL: two-run contract lost the separate effective-policy decision")
    divergences = record.get("organizations_divergences", [])
    if len(divergences) != 1:
        raise SystemExit("FAIL: two-run contract must report each Organizations divergence")
    divergence = divergences[0]
    if not divergence.get("action_name") or not divergence.get("resource_arn"):
        raise SystemExit("FAIL: Organizations divergence lacks action and resource attribution")
    sources = divergence.get("default", {}).get("matched_statement_sources", [])
    if not any(source.get("source_policy_type") == "Organizations Policy" for source in sources):
        raise SystemExit("FAIL: Organizations divergence lacks default-run source attribution")
if payload.get("summary", {}).get("organizations_divergences") != len(records):
    raise SystemExit("FAIL: two-run summary Organizations divergence count is wrong")
PY_VALIDATE_ROLE_TWO_RUNS
}

mutate_role_two_run_calls() {
  local source=$1
  local destination=$2
  python3 - "$source" "$destination" <<'PY_MUTATE_ROLE_TWO_RUNS'
import json
from pathlib import Path
import shutil
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
shutil.copytree(source, destination)
for path in sorted(destination.glob("*.json"), key=lambda item: int(item.stem)):
    args = json.loads(path.read_text(encoding="utf-8"))
    if args[:2] == ["iam", "simulate-principal-policy"] and "--policy-exclusion-list" in args:
        index = args.index("--policy-exclusion-list")
        del args[index:index + 2]
        path.write_text(json.dumps(args) + "\n", encoding="utf-8")
        break
else:
    raise SystemExit("FAIL: two-run mutation found no scp-excluded simulation")
PY_MUTATE_ROLE_TWO_RUNS
}


run_full_scale_role_dry_run() {
  local role_lane=$1
  local output_path=$2
  local plan="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json"
  local vectors="$REPO_ROOT/tests/fixtures/iam-simulate/vectors"
  local timeout_seconds=${IAM_SIM_FULL_SCALE_TIMEOUT_SECONDS:-20}
  python3 - "$role_lane" "$plan" "$vectors" "$output_path" "$timeout_seconds" \
    "$phase2_dir" "$IAM_SIM_AWS_WRAPPER" <<'PY_RUN_FULL_ROLE_DRY'
from pathlib import Path
import os
import signal
import subprocess
import sys

role_lane, plan, vectors, output_path, timeout_seconds, phase2_dir, wrapper = sys.argv[1:]
environment = os.environ.copy()
environment.pop("AWS_PROFILE", None)
environment.update({
    "PATH": f"{phase2_dir}/bin:{environment['PATH']}",
    "AWS_CLI_BIN": "aws",
    "AWS_CLI_SH": wrapper,
    "FAKE_AWS_CALL_DIR": f"{phase2_dir}/calls",
    "FAKE_ROLE_STATE_DIR": f"{phase2_dir}/roles",
    "FAKE_AWS_SCENARIO": "success",
    "FAKE_ACCOUNT_ID": "000000000000",
    "IAM_SIM_RUN_ID": "full-fixture",
    "TARGET": "aws",
})
command = [
    role_lane,
    "--plan", plan,
    "--vectors", vectors,
    "--report", f"{phase2_dir}/full-fixture-dry-report.json",
    "--expect-account", "000000000000",
    "--dry-run",
]
process = subprocess.Popen(
    command,
    env=environment,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    start_new_session=True,
)
try:
    output, _ = process.communicate(timeout=int(timeout_seconds))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    try:
        output, _ = process.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
    Path(output_path).write_text(output, encoding="utf-8")
    raise SystemExit(
        f"FAIL: full-fixture role-lane dry-run exceeded {timeout_seconds} seconds"
    )
Path(output_path).write_text(output, encoding="utf-8")
if process.returncode != 0:
    raise SystemExit(
        f"FAIL: full-fixture role-lane dry-run exited {process.returncode}"
    )
PY_RUN_FULL_ROLE_DRY
}

validate_full_scale_role_dry_run() {
  local inventory=$1
  local plan="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json"
  local vectors="$REPO_ROOT/tests/fixtures/iam-simulate/vectors"
  python3 - "$inventory" "$plan" "$vectors" <<'PY_VALIDATE_FULL_ROLE_DRY'
from collections import Counter
import json
from pathlib import Path
import re
import sys

inventory_path = Path(sys.argv[1])
plan_path = Path(sys.argv[2])
vectors_path = Path(sys.argv[3])
role_for_document = {
    "aws_iam_role_policy.plan_reader_deny": "plan-reader",
    "aws_iam_role_policy.plan_reader_state": "plan-reader",
    "aws_iam_policy.deployer_state": "deployer",
    "aws_iam_policy.deployer_ec2": "deployer",
    "aws_iam_policy.deployer_elb_ecs": "deployer",
    "aws_iam_policy.deployer_data": "deployer",
    "aws_iam_policy.deployer_iam": "deployer",
    "aws_iam_policy.deployer_guard": "deployer",
    "aws_iam_role_policy.publisher": "publisher",
}
plan = json.loads(plan_path.read_text(encoding="utf-8"))
resources = plan["planned_values"]["root_module"]["resources"]
documents = {
    resource["address"]: resource["values"]["policy"]
    for resource in resources
    if resource.get("address") in role_for_document
}
vectors = [
    json.loads(path.read_text(encoding="utf-8"))
    for path in sorted(vectors_path.rglob("*.json"))
]
selected = [
    vector for vector in vectors
    if vector.get("simulation_mode") == "custom"
    and vector.get("document") in role_for_document
]
selected_roles = {
    role_for_document[vector["document"]]
    for vector in selected
}
role_count = 0
for role in selected_roles:
    addresses = sorted(
        address for address, mapped_role in role_for_document.items()
        if mapped_role == role
    )
    policies = [json.loads(documents[address]) for address in addresses]
    versions = {policy["Version"] for policy in policies}
    statements = []
    for policy in policies:
        policy_statements = policy["Statement"]
        statements.extend(
            policy_statements if isinstance(policy_statements, list)
            else [policy_statements]
        )
    combined = json.dumps(
        {"Version": next(iter(versions)), "Statement": statements},
        separators=(",", ":"),
    )
    role_count += (
        1 if len(re.sub(r"\s", "", combined)) <= 10240
        else len(addresses)
    )

case_count = len(selected)
expected_calls = 1 + 8 * role_count + 2 * case_count
lines = [
    line for line in inventory_path.read_text(encoding="utf-8").splitlines()
    if line.startswith("DRY-RUN:")
]
if len(lines) != expected_calls:
    raise SystemExit(
        "FAIL: full-fixture dry-run call count is "
        f"{len(lines)}, expected 1 + 8*{role_count} + 2*{case_count} = {expected_calls}"
    )

operations = Counter()
for operation in (
    "create-role", "list-role-tags", "put-role-policy",
    "simulate-principal-policy", "delete-role-policy", "delete-role", "get-role",
):
    operations[operation] = sum(
        re.search(rf" iam {operation}(?: |$)", line) is not None
        for line in lines
    )
expected_operations = {
    "create-role": role_count,
    "list-role-tags": 3 * role_count,
    "put-role-policy": role_count,
    "simulate-principal-policy": 2 * case_count,
    "delete-role-policy": role_count,
    "delete-role": role_count,
    "get-role": role_count,
}
if dict(operations) != expected_operations:
    raise SystemExit(
        f"FAIL: full-fixture dry-run operation counts differ: {dict(operations)}"
    )
if sum(" sts get-caller-identity " in line for line in lines) != 1:
    raise SystemExit("FAIL: full-fixture dry-run requires one caller identity call")

simulations = [line for line in lines if " iam simulate-principal-policy " in line]
exclusion = r' --policy-exclusion-list \{\"PolicyType\":\"scp\"\}'
for index in range(0, len(simulations), 2):
    excluded, default = simulations[index:index + 2]
    if not excluded.endswith(exclusion) or excluded[:-len(exclusion)] != default:
        raise SystemExit(
            "FAIL: full-fixture dry-run must emit scp-excluded then default for each case"
        )
print(f"R={role_count} C={case_count} calls={expected_calls}")
PY_VALIDATE_FULL_ROLE_DRY
}

mutate_role_array_reads() {
  local source_path=$1
  local destination=$2
  python3 - "$source_path" "$destination" "$REPO_ROOT" <<'PY_MUTATE_ROLE_ARRAY_READS'
from pathlib import Path
import shlex
import sys

source_path = Path(sys.argv[1])
destination = Path(sys.argv[2])
source = source_path.read_text(encoding="utf-8")
root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
if source.count(root_line) != 1:
    raise SystemExit("FAIL: role array-read mutation root anchor changed")
source = source.replace(root_line, f"REPO_ROOT={shlex.quote(sys.argv[3])}")
replacements = {
    "    jq -r '.action_names[]' <<<\"$case_json\" >\"$tmp_dir/action-names\"\n"
    "    while IFS= read -r value; do actions+=(\"$value\"); done <\"$tmp_dir/action-names\"":
        "    while IFS= read -r value; do actions+=(\"$value\"); done "
        "< <(jq -r '.action_names[]' <<<\"$case_json\")",
    "    jq -r '.resource_arns[]' <<<\"$case_json\" >\"$tmp_dir/resource-arns\"\n"
    "    while IFS= read -r value; do resources+=(\"$value\"); done <\"$tmp_dir/resource-arns\"":
        "    while IFS= read -r value; do resources+=(\"$value\"); done "
        "< <(jq -r '.resource_arns[]' <<<\"$case_json\")",
    "  jq -r '.action_names[]' <<<\"$case_json\" >\"$tmp_dir/action-names\"\n"
    "  while IFS= read -r value; do actions+=(\"$value\"); done <\"$tmp_dir/action-names\"":
        "  while IFS= read -r value; do actions+=(\"$value\"); done "
        "< <(jq -r '.action_names[]' <<<\"$case_json\")",
    "  jq -r '.resource_arns[]' <<<\"$case_json\" >\"$tmp_dir/resource-arns\"\n"
    "  while IFS= read -r value; do resources+=(\"$value\"); done <\"$tmp_dir/resource-arns\"":
        "  while IFS= read -r value; do resources+=(\"$value\"); done "
        "< <(jq -r '.resource_arns[]' <<<\"$case_json\")",
}
for bounded, leaking in replacements.items():
    if source.count(bounded) != 1:
        raise SystemExit(f"FAIL: role array-read mutation anchor changed: {bounded!r}")
    source = source.replace(bounded, leaking)
destination.write_text(source, encoding="utf-8")
PY_MUTATE_ROLE_ARRAY_READS
  chmod +x "$destination"
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

run_role_shared_mapping_case() {
  local name=$1
  local label=$2
  local plan=$3
  local vectors=$4
  local custom_report=$5
  local response=$6
  local expected_sid=$7
  local report="$phase2_dir/role-shared-$name-report.json"
  local output rc
  reset_phase2_fake
  set +e
  output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    IAM_SIM_TEST_ROLE_PLAN="$plan" \
    IAM_SIM_TEST_ROLE_VECTORS="$vectors" \
    IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$custom_report" \
    IAM_SIM_TEST_ROLE_REPORT="$report" \
    IAM_SIM_TEST_PRINCIPAL_RESPONSE="$response" \
    run_phase2_role_lane success 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] && jq -e --arg sid "$expected_sid" '
    .records | length == 1
    and .[0].pass == true
    and .[0].source_document_hash_agrees_with_custom_lane == true
    and .[0].scp_excluded.decision_observed == "allowed"
    and .[0].default.decision_observed == "allowed"
    and (if $sid == "" then
      .[0].scp_excluded.matched_sids == [] and .[0].default.matched_sids == []
    else
      .[0].scp_excluded.matched_sids == [$sid] and .[0].default.matched_sids == [$sid]
    end)
  ' "$report" >/dev/null; then
    pass_case "$label"
  else
    fail_case "$label" "rc=$rc output=$output"
  fi
}

run_iam_simulate_role_lane_contracts() {
  local output rc mutated_inventory full_inventory full_scale role_lane_mutant
  local account account_mutant account_report cleanup_mutant cleanup_report
  local mutant_inventory mutated_full_inventory mutation_fail mutation_output mutation_rc
  local core_mutant expected_sid expected_hash_failure wrong_hash_report nonce_report fail_line
  local wrong_mode_report wrong_mode_case_id expected_mode_failure
  echo "== iam simulate contracts: ROLE-LANE =="
  group_failures=$failures

  if [ ! -x "$IAM_SIM_ROLE_LANE" ]; then
    fail_case "role-lane runner exists and is executable" "$IAM_SIM_ROLE_LANE is missing"
  else
    run_role_shared_mapping_case \
      "deployer-position" \
      "role-lane maps real deployer_data delimiter-inclusive exclusive-end range" \
      "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      "$phase2_dir/deployer-position-vectors" \
      "$phase2_dir/role-deployer-position-custom-report.json" \
      "$phase2_dir/response-deployer-position.json" \
      "ClickhouseSecretCreateWithTag"
    for name in string-delimiters escaped-quotes; do
      expected_sid=DenyReadStateObjectsOutsideScope
      [ "$name" != escaped-quotes ] || expected_sid=DenyListBucketOutsideScope
      run_role_shared_mapping_case \
        "scanner-$name" \
        "role-lane scans exact statement spans with $name" \
        "$phase2_dir/plan-scanner-position.json" \
        "$phase2_dir/scanner-$name-vectors" \
        "$phase2_dir/role-scanner-$name-custom-report.json" \
        "$phase2_dir/response-scanner-$name.json" \
        "$expected_sid"
    done
    run_role_shared_mapping_case \
      "action-level" \
      "role-lane uses action-level decision when ResourceSpecificResults is absent" \
      "$phase2_plan" \
      "$phase2_dir/role-action-level-vectors" \
      "$phase2_dir/role-action-level-custom-report.json" \
      "$phase2_dir/response-role-action-level.json" \
      ""

    core_mutant="$phase2_dir/iam-simulate-core-role-strict-containment.py"
    mutate_shared_core_overlap "$core_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_CORE="$core_mutant" \
      IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/deployer-position-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-deployer-position-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-shared-core-mutant-report.json" \
      IAM_SIM_TEST_PRINCIPAL_RESPONSE="$phase2_dir/response-deployer-position.json" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'FAIL: unmapped matched statement position from PolicyInputList.1' \
         <<<"$output"; then
      pass_case "role-lane shared-core unique-overlap mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane shared-core unique-overlap mutation did not fail as required" \
        "rc=$rc output=$output"
    fi
    run_role_shared_mapping_case \
      "shared-core-restored" \
      "role-lane shared-core mutation restored PASS" \
      "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      "$phase2_dir/deployer-position-vectors" \
      "$phase2_dir/role-deployer-position-custom-report.json" \
      "$phase2_dir/response-deployer-position.json" \
      "ClickhouseSecretCreateWithTag"

    account=123456
    account+='789012'
    account_mutant="$phase2_dir/iam-simulate-roles-account-redaction-mutant.sh"
    account_report="$phase2_dir/role-account-redaction-mutant-report.json"
    mutate_role_report_redaction "$IAM_SIM_ROLE_LANE" "$account_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ACCOUNT_ID="$account" \
      IAM_SIM_TEST_RUN_ID="fixture-$account" \
      IAM_SIM_TEST_ROLE_LANE="$account_mutant" \
      IAM_SIM_TEST_ROLE_REPORT="$account_report" \
      run_phase2_role_lane verify-present 2>&1)"
    rc=$?
    set -e
    set +e
    mutation_output="$(validate_role_account_redaction \
      "$account_report" "$phase2_calls" "$account" 2>&1)"
    mutation_rc=$?
    set -e
    mutation_fail="$(grep -m1 '^FAIL:' <<<"$mutation_output" || true)"
    if [ "$rc" -ne 0 ] && grep -Fq 'manual cleanup: role still exists' <<<"$output" && \
       [ "$mutation_rc" -ne 0 ] && \
       grep -Fq "FAIL: role report contains unredacted 12-digit account id: $account" <<<"$mutation_output"; then
      pass_case "role-lane report account redaction mutation -> $mutation_fail"
    else
      fail_case "role-lane report account redaction mutation did not fail as required" \
        "runner_rc=$rc validation_rc=$mutation_rc runner=$output validation=$mutation_output"
    fi

    account_report="$phase2_dir/role-account-redaction-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ACCOUNT_ID="$account" \
      IAM_SIM_TEST_RUN_ID="fixture-$account" \
      IAM_SIM_TEST_ROLE_REPORT="$account_report" \
      run_phase2_role_lane verify-present 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fq 'manual cleanup: role still exists' <<<"$output" && \
       validate_role_account_redaction "$account_report" "$phase2_calls" "$account"; then
      pass_case "role-lane report account redaction mutation restored PASS"
    else
      fail_case "role-lane report account redaction mutation restoration" \
        "rc=$rc output=$output"
    fi

    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && validate_role_selection_report "$phase2_dir/role-report.json"; then
      pass_case "role-lane selects custom vectors and records custom-isolated exclusion"
      mutate_role_selection_report "$phase2_dir/role-report.json" \
        "$phase2_dir/role-selection-mutant.json"
      expect_failure "role-lane selection reason" \
        "must record one custom-isolated exclusion with its reason" \
        validate_role_selection_report "$phase2_dir/role-selection-mutant.json"
      if validate_role_selection_report "$phase2_dir/role-report.json"; then
        pass_case "role-lane selection reason mutation restored PASS"
      else
        fail_case "role-lane selection reason mutation restoration"
      fi
    else
      fail_case "role-lane selects custom vectors and records custom-isolated exclusion" \
        "rc=$rc output=$output"
    fi

    reset_phase2_fake
    projection_report="$phase2_dir/role-projection-report.json"
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$projection_report" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && \
       validate_role_projection_report \
         "$projection_report" "$phase2_dir/role-projection-vectors" \
         "$phase2_dir/role-projection-plan.json" "$phase2_calls" && \
       [ "$(phase2_call_count iam create-role)" -eq 8 ] && \
       [ "$(phase2_call_count iam put-role-policy)" -eq 8 ] && \
       [ "$(phase2_call_count iam delete-role-policy)" -eq 8 ] && \
       [ "$(phase2_call_count iam delete-role)" -eq 8 ] && \
       [ "$(phase2_call_count iam get-role)" -eq 8 ]; then
      pass_case "role-lane projects fitting roles combined and deployer in six complete passes"
      mutate_role_projection_report "$projection_report" \
        "$phase2_dir/role-projection-mutant.json"
      expect_failure "role-lane projection pass count" \
        "role projection requires eight passes" \
        validate_role_projection_report \
          "$phase2_dir/role-projection-mutant.json" \
          "$phase2_dir/role-projection-vectors" \
          "$phase2_dir/role-projection-plan.json" "$phase2_calls"
      if validate_role_projection_report \
        "$projection_report" "$phase2_dir/role-projection-vectors" \
        "$phase2_dir/role-projection-plan.json" "$phase2_calls"; then
        pass_case "role-lane projection pass count mutation restored PASS"
      else
        fail_case "role-lane projection pass count mutation restoration"
      fi
    else
      fail_case "role-lane projects fitting roles combined and deployer in six complete passes" \
        "rc=$rc output=$output"
    fi

    wrong_hash_report="$phase2_dir/role-projection-wrong-hash-custom-report.json"
    expected_hash_failure="$(role_wrong_hash_expected_line \
      "$phase2_dir/role-projection-plan.json" \
      "$phase2_dir/role-projection-vectors" "$wrong_hash_report")"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$wrong_hash_report" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-projection-wrong-hash-report.json" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fxq "$expected_hash_failure" <<<"$output" && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane wrong-hash preflight mutation -> $expected_hash_failure"
    else
      fail_case "role-lane wrong-hash preflight mutation did not fail before create" \
        "rc=$rc create_calls=$(phase2_call_count iam create-role) output=$output"
    fi
    wrong_mode_report="$phase2_dir/role-projection-wrong-mode-custom-report.json"
    wrong_mode_case_id="$(jq -r '.records[] | select(.mode == "principal") | .case_id' \
      "$wrong_mode_report")"
    expected_mode_failure="FAIL: custom report mode mismatch for $wrong_mode_case_id: report='principal' vector='custom'"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$wrong_mode_report" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-projection-wrong-mode-report.json" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fxq "$expected_mode_failure" <<<"$output" && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane wrong-mode preflight mutation -> $expected_mode_failure"
    else
      fail_case "role-lane wrong-mode preflight mutation did not fail before create" \
        "rc=$rc create_calls=$(phase2_call_count iam create-role) output=$output"
    fi
    run_role_projection_restored_case "role-lane wrong-hash preflight"

    reset_phase2_fake
    set +e
    output="$(IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-duplicate-sid-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      run_phase2_role_lane success --dry-run 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq \
         'FAIL: duplicate Sid CrossDocumentDuplicate across aws_iam_role_policy.plan_reader_deny and aws_iam_role_policy.plan_reader_state' \
         <<<"$output" && \
       [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
      pass_case "role-lane duplicate Sid mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane duplicate Sid mutation did not fail as required" \
        "rc=$rc output=$output"
    fi

    reset_phase2_fake
    if output="$(IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      run_phase2_role_lane success --dry-run 2>&1)" && \
       [ "$(grep -Ec 'iam create-role( |$)' <<<"$output" || true)" -eq 8 ]; then
      pass_case "role-lane duplicate Sid mutation restored projection passes"
    else
      fail_case "role-lane duplicate Sid mutation restored projection passes" "$output"
    fi

    reset_phase2_fake
    divergence_report="$phase2_dir/role-divergence-report.json"
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-divergence-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$divergence_report" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && validate_role_divergence_report "$divergence_report"; then
      pass_case "role-lane records custom-lane divergence without failing"
      mutate_role_divergence_report "$divergence_report" \
        "$phase2_dir/role-divergence-mutant.json"
      expect_failure "role-lane divergence evidence" \
        "role divergence summary must contain two agreements and one divergence" \
        validate_role_divergence_report "$phase2_dir/role-divergence-mutant.json"
      if validate_role_divergence_report "$divergence_report"; then
        pass_case "role-lane divergence evidence mutation restored PASS"
      else
        fail_case "role-lane divergence evidence mutation restoration"
      fi
    else
      fail_case "role-lane records custom-lane divergence without failing" \
        "rc=$rc output=$output"
    fi

    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-missing-custom-report.json" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'FAIL: custom report lacks exactly one record for ' <<<"$output" && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane missing custom case mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane missing custom case mutation did not fail before create as required" \
        "rc=$rc create_calls=$(phase2_call_count iam create-role) output=$output"
    fi
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      run_phase2_role_lane success 2>&1)"; then
      pass_case "role-lane missing custom case mutation restored complete report passes"
    else
      fail_case "role-lane missing custom case mutation restored complete report passes" "$output"
    fi

    reset_phase2_fake
    organizations_report="$phase2_dir/role-organizations-report.json"
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_REPORT="$organizations_report" \
      run_phase2_role_lane organizations-difference 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && \
       validate_role_two_runs "$phase2_calls" "$organizations_report"; then
      pass_case "role-lane issues both runs and compares the scp-excluded result"
      mutate_role_two_run_calls "$phase2_calls" "$phase2_dir/two-run-calls-mutant"
      expect_failure "role-lane two-run call shape" \
        "two-run contract requires one exact scp-excluded call and one default call per case" \
        validate_role_two_runs \
          "$phase2_dir/two-run-calls-mutant" "$organizations_report"
      if validate_role_two_runs "$phase2_calls" "$organizations_report"; then
        pass_case "role-lane two-run call shape mutation restored PASS"
      else
        fail_case "role-lane two-run call shape mutation restoration"
      fi
    else
      fail_case "role-lane issues both runs and compares the scp-excluded result" \
        "rc=$rc output=$output"
    fi

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

    full_inventory="$phase2_dir/full-fixture-dry-run.txt"
    reset_phase2_fake
    set +e
    output="$(run_full_scale_role_dry_run \
      "$IAM_SIM_ROLE_LANE" "$full_inventory" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && \
       full_scale="$(validate_full_scale_role_dry_run "$full_inventory" 2>&1)" && \
       [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
      pass_case "role-lane full-fixture dry-run terminates with formula count ($full_scale)"

      mutated_full_inventory="$phase2_dir/full-fixture-call-count-mutant.txt"
      sed '1d' "$full_inventory" >"$mutated_full_inventory"
      expect_failure "role-lane full-fixture formula count" \
        "full-fixture dry-run call count is" \
        validate_full_scale_role_dry_run "$mutated_full_inventory"
      if full_scale="$(validate_full_scale_role_dry_run "$full_inventory" 2>&1)"; then
        pass_case "role-lane full-fixture formula count mutation restored PASS ($full_scale)"
      else
        fail_case "role-lane full-fixture formula count mutation restoration" "$full_scale"
      fi

      role_lane_mutant="$phase2_dir/iam-simulate-roles-array-read-mutant.sh"
      mutate_role_array_reads "$IAM_SIM_ROLE_LANE" "$role_lane_mutant"
      mutant_inventory="$phase2_dir/full-fixture-mutant-dry-run.txt"
      expect_failure "role-lane full-fixture array-read" \
        "full-fixture role-lane dry-run exceeded" \
        run_full_scale_role_dry_run "$role_lane_mutant" "$mutant_inventory"

      reset_phase2_fake
      if run_full_scale_role_dry_run \
           "$IAM_SIM_ROLE_LANE" "$full_inventory" >/dev/null 2>&1 && \
         full_scale="$(validate_full_scale_role_dry_run "$full_inventory" 2>&1)" && \
         [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
        pass_case "role-lane full-fixture array-read mutation restored PASS ($full_scale)"
      else
        fail_case "role-lane full-fixture array-read mutation restoration" \
          "${full_scale:-validation did not run}"
      fi
    else
      fail_case "role-lane full-fixture dry-run terminates with formula count" \
        "rc=$rc emitted_calls=$(grep -c '^DRY-RUN:' "$full_inventory" 2>/dev/null || true) output=$output"
    fi

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

    nonce_report="$phase2_dir/role-nonce-tamper-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$nonce_report" \
      IAM_SIM_TEST_ROLE_INJECTION_SUFFIX=-deployer-p4 \
      run_phase2_role_lane nonce-tamper 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'FAIL: ownership tag mismatch for orbit-iam-sim-fixture-run-deployer-p4' \
         <<<"$output" && \
       validate_role_nonce_tamper "$nonce_report" "$phase2_calls" "$phase2_roles"; then
      pass_case "role-lane nonce tamper at deployer p4 mutation -> $fail_line"
    else
      fail_case "role-lane nonce tamper at deployer p4 mutation did not fail closed" \
        "rc=$rc output=$output"
    fi
    role_lane_mutant="$phase2_dir/iam-simulate-roles-nonce-ignoring-mutant.sh"
    mutate_role_nonce_check "$IAM_SIM_ROLE_LANE" "$role_lane_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-nonce-mutant-report.json" \
      IAM_SIM_TEST_ROLE_INJECTION_SUFFIX=-deployer-p4 \
      IAM_SIM_TEST_ROLE_LANE="$role_lane_mutant" \
      run_phase2_role_lane nonce-tamper 2>&1)"
    rc=$?
    set -e
    set +e
    mutation_output="$(validate_role_nonce_tamper \
      "$phase2_dir/role-nonce-mutant-report.json" \
      "$phase2_calls" "$phase2_roles" 2>&1)"
    mutation_rc=$?
    set -e
    mutation_fail="$(grep -m1 '^FAIL:' <<<"$mutation_output" || true)"
    if [ "$rc" -eq 0 ] && [ "$mutation_rc" -ne 0 ] && \
       grep -Fq 'FAIL: nonce tamper reached policy or role mutations:' \
         <<<"$mutation_output"; then
      pass_case "role-lane nonce-ignoring mutant -> $mutation_fail"
    else
      fail_case "role-lane nonce-ignoring mutant was not killed" \
        "runner_rc=$rc validation_rc=$mutation_rc runner=$output validation=$mutation_output"
    fi

    nonce_report="$phase2_dir/role-nonce-tamper-restored-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$nonce_report" \
      IAM_SIM_TEST_ROLE_INJECTION_SUFFIX=-deployer-p4 \
      run_phase2_role_lane nonce-tamper 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && validate_role_nonce_tamper \
      "$nonce_report" "$phase2_calls" "$phase2_roles"; then
      pass_case "role-lane nonce-ignoring mutant restored PASS"
    else
      fail_case "role-lane nonce-ignoring mutant restoration" "rc=$rc output=$output"
    fi
    run_role_projection_restored_case "role-lane nonce tamper"

    expect_role_failure "role-lane EntityAlreadyExists isolation" "manual cleanup: role already existed at create time" entity-exists
    if [ "$(phase2_call_count iam delete-role-policy)" -ne 0 ] || \
       [ "$(phase2_call_count iam delete-role)" -ne 0 ]; then
      fail_case "role-lane EntityAlreadyExists isolation" "collision caused a delete"
    fi

    run_role_creation_failure_case \
      "role-lane midway create cleanup (3 roles)" create-midway "create-role failed" \
      3 2 1 "$phase2_plan" "$phase2_dir/role-vectors" \
      "$phase2_dir/role-custom-report.json"
    run_role_creation_failure_case \
      "role-lane midway create cleanup (8 roles at deployer p4)" \
      create-midway "create-role failed" 8 5 4 \
      "$phase2_dir/role-projection-plan.json" \
      "$phase2_dir/role-projection-vectors" \
      "$phase2_dir/role-projection-custom-report.json"

    cleanup_mutant="$phase2_dir/iam-simulate-roles-high-index-cleanup-mutant.sh"
    mutate_role_cleanup_high_indices "$IAM_SIM_ROLE_LANE" "$cleanup_mutant"
    run_role_creation_failure_case \
      "role-lane high-index cleanup mutation retains 3-role PASS" \
      create-midway "create-role failed" 3 2 1 \
      "$phase2_plan" "$phase2_dir/role-vectors" \
      "$phase2_dir/role-custom-report.json" "$cleanup_mutant"

    cleanup_report="$phase2_dir/role-high-index-cleanup-mutant-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$cleanup_report" \
      IAM_SIM_TEST_ROLE_FAILURE_CREATE_INDEX=5 \
      IAM_SIM_TEST_ROLE_LANE="$cleanup_mutant" \
      run_phase2_role_lane create-midway 2>&1)"
    rc=$?
    set -e
    set +e
    mutation_output="$(validate_role_creation_failure \
      "$cleanup_report" "$phase2_calls" 8 5 4 2>&1)"
    mutation_rc=$?
    set -e
    mutation_fail="$(grep -m1 '^FAIL:' <<<"$mutation_output" || true)"
    if [ "$rc" -ne 0 ] && grep -Fq 'create-role failed' <<<"$output" && \
       [ "$mutation_rc" -ne 0 ] && \
       grep -Fq 'FAIL: role failure cleanup did not delete every created role in reverse order' \
         <<<"$mutation_output" && \
       find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      pass_case "role-lane high-index cleanup 8-role mutation -> $mutation_fail"
    else
      fail_case "role-lane high-index cleanup 8-role mutation did not fail as required" \
        "runner_rc=$rc validation_rc=$mutation_rc runner=$output validation=$mutation_output"
    fi
    run_role_creation_failure_case \
      "role-lane high-index cleanup mutation restored 8-role PASS" \
      create-midway "create-role failed" 8 5 4 \
      "$phase2_dir/role-projection-plan.json" \
      "$phase2_dir/role-projection-vectors" \
      "$phase2_dir/role-projection-custom-report.json"

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

    run_role_creation_failure_case \
      "role-lane TERM cleanup (3 roles)" term-during-create "terminated by TERM" \
      3 1 1 "$phase2_plan" "$phase2_dir/role-vectors" \
      "$phase2_dir/role-custom-report.json"
    run_role_creation_failure_case \
      "role-lane TERM cleanup (8 roles at deployer p4)" \
      term-during-create "terminated by TERM" 8 5 5 \
      "$phase2_dir/role-projection-plan.json" \
      "$phase2_dir/role-projection-vectors" \
      "$phase2_dir/role-projection-custom-report.json"

    run_role_cleanup_race_case \
      "role-lane TERM between put and marker (8 roles at deployer p4)" \
      term-during-put 143 "FAIL: terminated by TERM"
    run_role_projection_restored_case "role-lane TERM between put and marker"

    run_role_cleanup_race_case \
      "role-lane unattached-policy NoSuchEntity cleanup (8 roles at deployer p4)" \
      put-policy-fails 1 \
      "FAIL: put-role-policy failed for orbit-iam-sim-fixture-run-deployer-p4"
    run_role_projection_restored_case "role-lane unattached-policy NoSuchEntity cleanup"

    run_role_cleanup_race_case \
      "role-lane deferred TERM after delete-role-policy (8 roles at deployer p4)" \
      term-after-delete-policy 143 "FAIL: terminated by TERM"
    run_role_projection_restored_case "role-lane deferred TERM after delete-role-policy"

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
