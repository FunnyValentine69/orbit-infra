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
from copy import deepcopy
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

    runner_mutant="$phase2_dir/iam-simulate-strict-containment.sh"
    python3 - "$IAM_SIM_RUNNER" "$runner_mutant" "$REPO_ROOT" <<'PY_MUTANT'
from pathlib import Path
import shlex
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
overlap_line = "            if start < end and start < span_end and span_start < end"
strict_line = (
    "            if span_start <= start < span_end "
    "and span_start < end <= span_end"
)
if source.count(root_line) != 1 or source.count(overlap_line) != 1:
    raise SystemExit("FAIL: runner unique-overlap mutation anchors changed")
source = source.replace(root_line, f"REPO_ROOT={shlex.quote(sys.argv[3])}")
source = source.replace(overlap_line, strict_line)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY_MUTANT
    chmod +x "$runner_mutant"
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
      output="$(IAM_SIM_RUNNER="$runner_mutant" IAM_SIM_TEST_PLAN="$mutant_plan" \
        run_phase2_runner success "$mutant_response" "$mutant_vectors" \
          "$phase2_dir/strict-$name-report.json" 2>&1)"
      mutant_rc=$?
      set -e
      if [ "$mutant_rc" -ne 0 ] && \
         grep -Fq 'FAIL: unmapped matched statement position from PolicyInputList.1' \
           <<<"$output"; then
        pass_case "runner $name unique-overlap mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
      else
        fail_case "runner $name unique-overlap mutation did not fail as required" \
          "rc=$mutant_rc output=$output"
      fi
    done

    for name in string-delimiters escaped-quotes; do
      runner_mutant="$phase2_dir/iam-simulate-$name-mutant.sh"
      python3 - "$IAM_SIM_RUNNER" "$runner_mutant" "$REPO_ROOT" "$name" <<'PY_MUTANT'
from pathlib import Path
import shlex
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
scan_line = "                        statement, end = decoder.raw_decode(policy, start)"
if source.count(root_line) != 1 or source.count(scan_line) != 1:
    raise SystemExit("FAIL: runner scanner mutation anchors changed")
source = source.replace(root_line, f"REPO_ROOT={shlex.quote(sys.argv[3])}")
if sys.argv[4] == "string-delimiters":
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
source = source.replace(scan_line, mutation)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY_MUTANT
      chmod +x "$runner_mutant"
      reset_phase2_fake
      set +e
      output="$(IAM_SIM_RUNNER="$runner_mutant" \
        IAM_SIM_TEST_PLAN="$phase2_dir/plan-scanner-position.json" \
        run_phase2_runner success "$phase2_dir/response-scanner-$name.json" \
          "$phase2_dir/scanner-$name-vectors" \
          "$phase2_dir/$name-mutant-report.json" 2>&1)"
      mutant_rc=$?
      set -e
      if [ "$mutant_rc" -ne 0 ] && grep -Fq 'FAIL: cannot scan submitted statement:' \
        <<<"$output"; then
        pass_case "runner $name scanner mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
      else
        fail_case "runner $name scanner mutation did not fail as required" \
          "rc=$mutant_rc output=$output"
      fi
    done

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
  env -u AWS_PROFILE \
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
