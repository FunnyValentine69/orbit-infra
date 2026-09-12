#!/usr/bin/env python3
"""Table-driven fixtures and offline helpers for the IAM simulator contracts."""
from __future__ import annotations
from collections import Counter
from copy import deepcopy
import hashlib
import importlib.util
import json
import fnmatch
import os
import re, shlex, shutil, subprocess
from pathlib import Path
import signal
import sys
CORE_DOCUMENTS = ('aws_iam_role_policy.plan_reader_deny', 'aws_iam_role_policy.plan_reader_state', 'aws_iam_policy.task_boundary', 'aws_iam_policy.deployer_state', 'aws_iam_policy.deployer_ec2', 'aws_iam_policy.deployer_elb_ecs', 'aws_iam_policy.deployer_data', 'aws_iam_policy.deployer_iam', 'aws_iam_policy.deployer_guard', 'aws_iam_role_policy.publisher')
S3_DIFFERENT_AUTHORIZATION_ACTIONS = {'s3:DeleteBucketOwnershipControls', 's3:DeleteBucketPublicAccessBlock'}
REQUIRED_CONTEXT_ENTRIES = [{'ContextKeyName': 'aws:RequestTag/Project', 'ContextKeyValues': ['orbit-infra'], 'ContextKeyType': 'string'}]
BASE_VECTOR = {'schema_version': 1, 'document': 'aws_iam_role_policy.plan_reader_deny', 'sid': 'DenyReadStateObjectsOutsideScope', 'simulation_mode': 'custom', 'assertion_kind': 'decision', 'action_names': ['iam:GetRole'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': [], 'matched_sid_forbidden': []}}
ROLE_READINESS_CASES = {
    'role-vectors/role-0.json': {'action_names': ['iam:GetRole'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': ['ReadStateObjects'], 'matched_sid_forbidden': []}},
    'role-vectors/role-1.json': {'action_names': ['logs:DescribeLogGroups'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': ['LogsDescribeStarOnly'], 'matched_sid_forbidden': []}},
    'role-vectors/role-2.json': {'action_names': ['iam:GetRole'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': ['EcrAuth'], 'matched_sid_forbidden': []}},
    'role-projection-vectors/projection-0.json': {'sid': 'DenySecretsAndParams', 'case_id': 'case:aws_iam_role_policy.plan_reader_deny:DenySecretsAndParams:ALL:none:protected-resource', 'action_names': ['ssm:GetParameter'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'explicitDeny', 'matched_sid_required': ['DenySecretsAndParams'], 'matched_sid_forbidden': []}},
    'role-projection-vectors/projection-1.json': {'sid': 'ReadStateObjects', 'case_id': 'case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:none:matching', 'action_names': ['s3:GetObject'], 'resource_arns': ['arn:aws:s3:::orbit-infra-${SUFFIX}-tfstate/bootstrap/preview'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': ['ReadStateObjects'], 'matched_sid_forbidden': []}},
    'role-projection-vectors/projection-2.json': {'action_names': ['ecr:GetAuthorizationToken'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': ['EcrVerificationAuth'], 'matched_sid_forbidden': []}},
    'role-projection-vectors/projection-3.json': {'action_names': ['ec2:DescribeVpcs'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': ['Ec2DescribeStarOnly'], 'matched_sid_forbidden': []}},
    'role-projection-vectors/projection-4.json': {'action_names': ['tag:GetResources'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': ['TagInventoryStarOnly'], 'matched_sid_forbidden': []}},
    'role-projection-vectors/projection-5.json': {'action_names': ['iam:DeleteRole'], 'resource_arns': ['arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-deployer'], 'context_entries': [], 'expect': {'decision': 'explicitDeny', 'matched_sid_required': ['DenyMutatingOwnControlRoles'], 'matched_sid_forbidden': []}},
    'role-projection-vectors/projection-6.json': {'sid': 'DenyDeleteRolePermissionsBoundary', 'case_id': 'case:aws_iam_policy.deployer_iam:DenyDeleteRolePermissionsBoundary:ALL:none:protected-resource', 'action_names': ['iam:DeleteRolePermissionsBoundary'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'explicitDeny', 'matched_sid_required': ['DenyDeleteRolePermissionsBoundary'], 'matched_sid_forbidden': []}},
    'role-projection-vectors/projection-7.json': {'action_names': ['s3:GetObject'], 'resource_arns': ['arn:aws:s3:::orbit-infra-${SUFFIX}-tfstate/envs/preview/preview'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': ['StateAndLeaseObjects'], 'matched_sid_forbidden': []}},
    'role-projection-vectors/projection-8.json': {'action_names': ['ecr:GetAuthorizationToken'], 'resource_arns': ['*'], 'context_entries': [], 'expect': {'decision': 'allowed', 'matched_sid_required': ['EcrAuth'], 'matched_sid_forbidden': []}},
    'deployer-position-vectors/position.json': {'action_names': ['secretsmanager:CreateSecret', 'secretsmanager:TagResource'], 'resource_arns': ['arn:aws:secretsmanager:us-east-1:${ACCOUNT_ID}:secret:orbit-infra-${SUFFIX}-preview'], 'context_entries': REQUIRED_CONTEXT_ENTRIES, 'expect': {'decision': 'allowed', 'matched_sid_required': ['ClickhouseSecretCreateWithTag'], 'matched_sid_forbidden': []}},
}


def _authorization_action_groups(actions):
    special = {action.casefold() for action in S3_DIFFERENT_AUTHORIZATION_ACTIONS}
    direct = [action for action in actions if action.casefold() not in special]
    separate = [action for action in actions if action.casefold() in special]
    return [group for group in (direct, separate) if group]


PLAN_FIXTURES = (
    ('plan.json', 'synthetic', ()),
    ('plan-per-pair-sid.json', 'plan.json', (('policy', 'aws_iam_role_policy.plan_reader_deny', ('$ctx', 'per_pair_sid_policy')),)),
    ('plan-resources-object.json', 'plan.json', (('set', ('planned_values', 'root_module', 'resources'), {}),)),
    ('plan-duplicate-document.json', 'plan.json', (('duplicate-resource', 'aws_iam_role_policy.plan_reader_deny'),)),
    ('plan-null-policy.json', 'plan.json', (('policy', 'aws_iam_role_policy.plan_reader_deny', None),)),
    ('plan-null-role-name.json', 'plan.json', (('resource-value', 'aws_iam_role.plan_reader', 'name', None),)),
    ('plan-invalid-role-name.json', 'plan.json', (('resource-value', 'aws_iam_role.plan_reader', 'name', 'invalid-plan-reader'),)),
    ('plan-multiple-account-ids.json', 'plan.json', (('policy', 'aws_iam_role_policy.plan_reader_state', ('$ctx', 'second_account_policy')),)),
    ('plan-empty-sid.json', 'plan.json', (('statement-sid', 'aws_iam_role_policy.plan_reader_deny', 0, ''),)),
    ('plan-whitespace-sid.json', 'plan.json', (('statement-sid', 'aws_iam_role_policy.plan_reader_deny', 0, '   '),)),
    ('plan-real-position.json', 'plan.json', (('policy', 'aws_iam_role_policy.plan_reader_deny', ('$ctx', 'real_position_policy')),)),
    ('plan-multiline-position.json', 'plan.json', (('policy', 'aws_iam_role_policy.plan_reader_deny', ('$ctx', 'multiline_position_policy')),)),
    ('plan-scanner-position.json', 'plan.json', (('policy', 'aws_iam_role_policy.plan_reader_deny', ('$ctx', 'scanner_position_policy')),)),
    ('plan-missing-document.json', 'plan.json', (('drop-resource', 'aws_iam_policy.task_boundary'),)),
    ('plan-missing-sid.json', 'plan.json', (('policy', 'aws_iam_policy.deployer_data', ('$ctx', 'isolated_missing_policy')),)),
    ('plan-duplicate-sid.json', 'plan.json', (('policy', 'aws_iam_policy.deployer_data', ('$ctx', 'isolated_duplicate_policy')),)),
    ('role-projection-plan.json', 'projection-source', ()),
    ('role-duplicate-sid-plan.json', 'role-projection-plan.json', (('statement-sid', 'aws_iam_role_policy.plan_reader_deny', 0, 'CrossDocumentDuplicate'), ('statement-sid', 'aws_iam_role_policy.plan_reader_state', 0, 'CrossDocumentDuplicate'))),
)
VECTOR_FIXTURES = (
    ('per-pair-sid-vectors/per-pair.json', 'decision', (('set', ('case_id',), 'case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource'), ('set', ('action_names',), ['s3:GetObject', 's3:GetObjectVersion']), ('set', ('resource_arns',), ['*']), ('set', ('expect',), {'decision': 'allowed', 'matched_sid_required': ['DenyReadStateObjectsOutsideScope'], 'matched_sid_forbidden': []}))),
    ('runner-vectors/mapping.json', 'decision', (('set', ('case_id',), 'case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource'), ('set', ('action_names',), ['s3:GetObject']), ('set', ('resource_arns',), ['arn:aws:s3:::orbit-infra-${SUFFIX}-good/example', 'arn:aws:s3:::orbit-infra-${SUFFIX}-bad/example']), ('set', ('expect',), {'decision': 'explicitDeny', 'resource_decisions': {'arn:aws:s3:::orbit-infra-${SUFFIX}-good/example': 'allowed', 'arn:aws:s3:::orbit-infra-${SUFFIX}-bad/example': 'explicitDeny'}, 'matched_sid_required': ['FixtureAllow', 'DenyReadStateObjectsOutsideScope'], 'matched_sid_forbidden': []}))),
    ('real-position-vectors/position.json', 'decision', (('set', ('case_id',), 'case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource'), ('set', ('action_names',), ['s3:GetObject']), ('set', ('resource_arns',), ['arn:aws:s3:::orbit-infra-${SUFFIX}-tfstate/other/x']), ('set', ('expect', 'decision'), 'explicitDeny'), ('set', ('expect', 'matched_sid_required'), ['DenyReadStateObjectsOutsideScope']))),
    ('multiline-position-vectors/position.json', 'real-position-vectors/position.json', ()),
    ('scanner-string-delimiters-vectors/position.json', 'real-position-vectors/position.json', (('set', ('resource_arns',), ['arn:aws:s3:::orbit-infra-${SUFFIX}-delimiters/example']), ('set', ('expect',), {'decision': 'allowed', 'matched_sid_required': ['DenyReadStateObjectsOutsideScope'], 'matched_sid_forbidden': []}))),
    ('scanner-escaped-quotes-vectors/position.json', 'scanner-string-delimiters-vectors/position.json', (('set', ('case_id',), 'case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:protected-resource'), ('set', ('sid',), 'DenyListBucketOutsideScope'), ('set', ('resource_arns',), ['arn:aws:s3:::orbit-infra-${SUFFIX}-escaped/example']), ('set', ('expect', 'matched_sid_required'), ['DenyListBucketOutsideScope']))),
    ('deployer-position-vectors/position.json', 'decision', (('set', ('document',), 'aws_iam_policy.deployer_data'), ('set', ('sid',), 'ClickhouseSecretCreateWithTag'), ('set', ('case_id',), 'case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching'), ('set', ('action_names',), ['secretsmanager:CreateSecret']), ('set', ('resource_arns',), ['arn:aws:secretsmanager:us-east-1:${ACCOUNT_ID}:secret:orbit-infra-${SUFFIX}-x']), ('set', ('context_entries',), [{'ContextKeyName': 'aws:RequestTag/Project', 'ContextKeyValues': ['orbit-infra'], 'ContextKeyType': 'string'}]), ('set', ('expect', 'matched_sid_required'), ['ClickhouseSecretCreateWithTag']))),
    ('ambiguous-vectors/ambiguous.json', 'decision', (('set', ('document',), 'aws_iam_policy.task_boundary'), ('set', ('sid',), 'EcrAuth'), ('set', ('case_id',), 'case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:in-boundary'), ('set', ('permissions_boundary_policy_input_list',), ['aws_iam_policy.task_boundary']), ('set', ('action_names',), ['ecr:GetAuthorizationToken']), ('set', ('expect', 'matched_sid_required'), ['EcrAuth']))),
    ('no-resource-vectors/no-resource.json', 'ambiguous-vectors/ambiguous.json', (('set', ('resource_arns',), []),)),
    ('authorization-split-vectors/authorization-split.json', 'authorization-source', (('set', ('expect', 'matched_sid_required'), []),)),
    ('authorization-casefold-vectors/authorization-split.json', 'authorization-split-vectors/authorization-split.json', (('set', ('action_names', 5), 's3:deletebucketpublicaccessblock'),)),
    ('duplicate-vectors/duplicate-0.json', 'decision', (('set', ('document',), 'aws_iam_policy.deployer_data'), ('set', ('sid',), 'ClickhouseSecretCreateWithTag'), ('set', ('case_id',), ('$case', 0)), ('set', ('action_names',), ['secretsmanager:CreateSecret']), ('set', ('resource_arns',), ['arn:aws:secretsmanager:us-east-1:${ACCOUNT_ID}:secret:duplicate']))),
    ('duplicate-vectors/duplicate-1.json', 'duplicate-vectors/duplicate-0.json', (('set', ('case_id',), ('$case', 1)),)),
    ('isolated-vectors/isolated.json', 'isolated-source', (('set', ('expect', 'matched_sid_forbidden'), ['LogsCreateWithTag']),)),
    ('role-vectors/role-0.json', 'decision', (('set', ('document',), 'aws_iam_role_policy.plan_reader_state'), ('set', ('sid',), 'ReadStateObjects'), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns',), ['arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-fixture-0']))),
    ('role-vectors/role-1.json', 'role-vectors/role-0.json', (('set', ('document',), 'aws_iam_policy.deployer_data'), ('set', ('sid',), 'LogsDescribeStarOnly'), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-fixture-1'))),
    ('role-vectors/role-2.json', 'role-vectors/role-0.json', (('set', ('document',), 'aws_iam_role_policy.publisher'), ('set', ('sid',), 'EcrAuth'), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-fixture-2'))),
    ('role-vectors/role-excluded-boundary.json', 'decision', (('set', ('document',), 'aws_iam_policy.task_boundary'), ('set', ('sid',), 'EcrAuth'), ('set', ('case_id',), 'case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:outside-boundary'), ('set', ('synthetic_policy_input_list',), ['{"Version":"2012-10-17","Statement":[{"Sid":"VectorIdentityAllow","Effect":"Allow","Action":["s3:ListAllMyBuckets"],"Resource":["*"]}]}']), ('set', ('permissions_boundary_policy_input_list',), ['aws_iam_policy.task_boundary']), ('set', ('action_names',), ['s3:ListAllMyBuckets']), ('set', ('expect',), {'decision': 'implicitDeny', 'matched_sid_required': [], 'matched_sid_forbidden': ['EcrAuth']}))),
    ('role-vectors/role-isolated.json', 'isolated-source', ()),
    ('role-action-level-vectors/action-level.json', 'role-vectors/role-0.json', (('set', ('resource_arns',), ['*']), ('set', ('expect', 'matched_sid_required'), []))),
    ('role-action-level-vectors/readiness.json', 'role-vectors/role-0.json', (('set', ('case_id',), 'case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:resource:nonmatching'),)),
    ('role-empty-resource-vectors/empty.json', 'role-vectors/role-0.json', (('set', ('resource_arns',), []), ('set', ('expect', 'matched_sid_required'), []))),
    ('role-empty-resource-vectors/readiness.json', 'role-vectors/role-0.json', (('set', ('case_id',), 'case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:resource:nonmatching'),)),
    ('role-projection-vectors/projection-0.json', 'decision', (('set', ('document',), 'aws_iam_role_policy.plan_reader_deny'), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns',), ['arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-projection-0']))),
    ('role-projection-vectors/projection-1.json', 'role-projection-vectors/projection-0.json', (('set', ('document',), 'aws_iam_role_policy.plan_reader_state'), ('set', ('sid',), ('$sid', 0)), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-projection-1'))),
    ('role-projection-vectors/projection-2.json', 'role-projection-vectors/projection-0.json', (('set', ('document',), 'aws_iam_policy.deployer_data'), ('set', ('sid',), ('$sid', 0)), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-projection-2'))),
    ('role-projection-vectors/projection-3.json', 'role-projection-vectors/projection-0.json', (('set', ('document',), 'aws_iam_policy.deployer_ec2'), ('set', ('sid',), ('$sid', 0)), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-projection-3'))),
    ('role-projection-vectors/projection-4.json', 'role-projection-vectors/projection-0.json', (('set', ('document',), 'aws_iam_policy.deployer_elb_ecs'), ('set', ('sid',), ('$sid', 0)), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-projection-4'))),
    ('role-projection-vectors/projection-5.json', 'role-projection-vectors/projection-0.json', (('set', ('document',), 'aws_iam_policy.deployer_guard'), ('set', ('sid',), ('$sid', 0)), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-projection-5'))),
    ('role-projection-vectors/projection-6.json', 'role-projection-vectors/projection-0.json', (('set', ('document',), 'aws_iam_policy.deployer_iam'), ('set', ('sid',), ('$sid', 0)), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-projection-6'))),
    ('role-projection-vectors/projection-7.json', 'role-projection-vectors/projection-0.json', (('set', ('document',), 'aws_iam_policy.deployer_state'), ('set', ('sid',), ('$sid', 0)), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-projection-7'))),
    ('role-projection-vectors/projection-8.json', 'role-projection-vectors/projection-0.json', (('set', ('document',), 'aws_iam_role_policy.publisher'), ('set', ('sid',), ('$sid', 0)), ('set', ('case_id',), ('$case', 0)), ('set', ('resource_arns', 0), 'arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-projection-8'))),
)
RESPONSE_FIXTURES = (
    ('response-baseline.json', 'mapping', ()),
    ('response-multiple-concrete-action-level.json', 'response-baseline.json', (('delete', ('EvaluationResults', 0, 'ResourceSpecificResults')),)),
    ('response-real-position.json', 'real-position', ()),
    ('response-multiline-position.json', 'response-real-position.json', (('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 0, 'MatchedStatements', 0, 'StartPosition'), {'Line': 5, 'Column': 5}), ('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 0, 'MatchedStatements', 0, 'EndPosition'), {'Line': 5, 'Column': 102}))),
    ('response-scanner-string-delimiters.json', 'scanner-0', ()),
    ('response-scanner-escaped-quotes.json', 'scanner-1', ()),
    ('response-deployer-position.json', 'deployer-position', ()),
    ('response-deployer-ambiguous.json', 'response-deployer-position.json', (('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 0, 'MatchedStatements', 0, 'StartPosition', 'Column'), 1778),)),
    ('response-decision-mutant.json', 'response-baseline.json', (('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 0, 'EvalResourceDecision'), 'explicitDeny'),)),
    ('response-position-mutant.json', 'response-baseline.json', (('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 1, 'MatchedStatements'), [('$ctx', 'mapping_match0')]),)),
    ('response-per-pair-sid-mutant.json', 'per-pair-sid-mutant', ()),
    ('response-per-pair-sid-restored.json', 'per-pair-sid-restored', ()),
    ('response-per-pair-decision-mutant.json', 'response-per-pair-sid-restored.json', (("set", ("EvaluationResults", 1, "EvalDecision"), "explicitDeny"), ("set", ("EvaluationResults", 1, "ResourceSpecificResults", 0, "EvalResourceDecision"), "explicitDeny"))),
    ('response-missing-arn.json', 'response-baseline.json', (('delete', ('EvaluationResults', 0, 'ResourceSpecificResults', -1)),)),
    ('response-unmapped.json', 'response-baseline.json', (('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 1, 'MatchedStatements'), [('$ctx', 'unmapped_match')]),)),
    ('response-unknown-source.json', 'response-baseline.json', (('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 1, 'MatchedStatements'), [('$ctx', 'unknown_source_match')]),)),
    ('response-ambiguous.json', 'ambiguous', ()),
    ('response-resolved.json', 'response-ambiguous.json', (('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 0, 'MatchedStatements'), [('$ctx', 'ambiguous_resolved_match')]),)),
    ('response-action-level.json', 'response-resolved.json', (('action-level',),)),
    ('response-action-level-decision-mutant.json', 'response-action-level.json', (('set', ('EvaluationResults', 0, 'EvalDecision'), 'implicitDeny'),)),
    ('response-action-level-attribution-mutant.json', 'response-action-level.json', (('set', ('EvaluationResults', 0, 'MatchedStatements'), []),)),
    ('response-missing-concrete-arn.json', 'response-real-position.json', (('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 0, 'EvalResourceName'), 'arn:aws:s3:::orbit-infra-79s5rw-tfstate/different/x'),)),
    ('response-duplicate.json', 'duplicate', ()),
    ('response-empty.json', 'empty', ()),
    ('response-isolated.json', 'isolated', ()),
    ('response-isolated-mutant.json', 'response-isolated.json', (('all-resource-decisions', 'allowed'),)),
    ('response-isolated-position-mutant.json', 'response-isolated.json', (('set', ('EvaluationResults', 0, 'ResourceSpecificResults', 0, 'MatchedStatements'), [('$ctx', 'real_position_match')]),)),
    ('response-role-action-level.json', 'role-action-level', ()),
)
CUSTOM_REPORT_FIXTURES = (
    ('role-custom-report.json', ('records', (('role-vectors/role-0.json', 'aws_iam_role_policy.plan_reader_state', 'custom'), ('role-vectors/role-1.json', 'aws_iam_policy.deployer_data', 'custom'), ('role-vectors/role-2.json', 'aws_iam_role_policy.publisher', 'custom'), ('role-vectors/role-isolated.json', None, 'custom-isolated'), ('role-vectors/role-excluded-boundary.json', 'aws_iam_policy.task_boundary', 'custom'))), (('set', ('records', 4, 'document_hashes_submitted', 'policy_input_list'), ('$ctx', 'excluded_boundary_policy_hashes')), ('set', ('records', 4, 'document_hashes_submitted', 'permissions_boundary_policy_input_list'), ('$ctx', 'excluded_boundary_boundary_hashes')))),
    ('role-per-pair-custom-report.json', ('records', (('per-pair-sid-vectors/per-pair.json', 'per_pair_sid_policy', 'custom'),)), ()),
    ('role-deployer-position-custom-report.json', ('records', (('deployer-position-vectors/position.json', 'real_deployer_policy', 'custom'),)), ()),
    ('role-scanner-string-delimiters-custom-report.json', ('records', (('scanner-string-delimiters-vectors/position.json', 'scanner_position_policy', 'custom'),)), ()),
    ('role-scanner-escaped-quotes-custom-report.json', ('records', (('scanner-escaped-quotes-vectors/position.json', 'scanner_position_policy', 'custom'),)), ()),
    ('role-action-level-custom-report.json', ('records', (('role-action-level-vectors/action-level.json', 'aws_iam_role_policy.plan_reader_state', 'custom'),)), ()),
    ('role-empty-resource-custom-report.json', ('records', (('role-empty-resource-vectors/empty.json', 'aws_iam_role_policy.plan_reader_state', 'custom'),)), ()),
    ('role-authorization-split-custom-report.json', ('records', (('authorization-split-vectors/authorization-split.json', 'real_deployer_policy', 'custom'),)), (('set', ('records', 0, 'decision_observed'), ('$ctx', 'role_authorization_decision')),)),
    ('role-authorization-casefold-custom-report.json', ('records', (('authorization-casefold-vectors/authorization-split.json', 'real_deployer_policy', 'custom'),)), (('set', ('records', 0, 'decision_observed'), ('$ctx', 'role_authorization_casefold_decision')),)),
    ('role-divergence-custom-report.json', 'role-custom-report.json', (('set', ('records', 0, 'decision_observed'), 'implicitDeny'), ('set', ('records', 0, 'matched_sids'), ['CustomMatchedSid']), ('set', ('records', 0, 'pass'), False), ('set', ('summary', 'passed'), 3), ('set', ('summary', 'failed'), 1))),
    ('role-missing-custom-report.json', 'role-custom-report.json', (('delete', ('records', 0)), ('set', ('summary', 'total'), 3), ('set', ('summary', 'passed'), 3))),
    ('role-projection-custom-report.json', ('records', tuple(((f'role-projection-vectors/projection-{index}.json', '@document', 'custom') for index in range(9)))), ()),
    ('role-projection-wrong-hash-custom-report.json', 'role-projection-custom-report.json', (('set', ('records', 5, 'document_hashes_submitted', 'policy_input_list', 0, 'sha256'), '0' * 64),)),
    ('role-projection-wrong-mode-custom-report.json', 'role-projection-custom-report.json', (('set', ('records', 5, 'mode'), 'principal'),)),
)
ROLE_SCENARIOS = (
    ('success', None, {}),
    ('propagation-delay', 'success', {'propagation_delay_calls': 1}),
    ('propagation-readback-exhausted', 'success', {'propagation_delay_calls': 5}),
    ('propagation-readiness-exhausted', 'success', {'readiness_delay_calls': 5}),
    ('authorization-split', 'success', {'custom': 'authorization-split'}),
    ('context-required', 'success', {'expected_context_entries': REQUIRED_CONTEXT_ENTRIES}),
    ('throttle-once', 'success', {'failure': {'operation': 'simulate-custom-policy', 'at': 1, 'error': 'Throttling', 'exit': 254}}),
    ('throttle-always', 'throttle-once', {'failure.at': 'always', 'failure.error': 'RequestLimitExceeded'}),
    ('timeout', 'throttle-once', {'failure.at': 'always', 'failure.error': 'aws-cli.sh: AWS command timed out after 30s', 'failure.exit': 124, 'failure.raw': True}),
    ('entity-exists', 'success', {'failure': {'operation': 'create-role', 'at': 1, 'error': 'EntityAlreadyExists', 'exit': 254}}),
    ('create-midway', 'entity-exists', {'failure.at': '$FAKE_ROLE_FAILURE_CREATE_INDEX', 'failure.default': 2, 'failure.error': 'ServiceFailure'}),
    ('nonce-tamper', 'success', {'tamper_tag': {'operation': 'create-role', 'key': 'OrbitIamSimulationNonce', 'suffix': '$FAKE_ROLE_INJECTION_SUFFIX'}}),
    ('term-during-create', 'success', {'signal': {'operation': 'create-role', 'at': '$FAKE_ROLE_FAILURE_CREATE_INDEX', 'default': 1, 'suffix': None}}),
    ('tag-mismatch', 'success', {'tamper_tag': {'operation': 'list-role-tags', 'key': 'OrbitIamSimulationRun', 'value': 'wrong-run'}}),
    ('put-policy-fails', 'success', {'failure': {'operation': 'put-role-policy', 'at': 'suffix', 'suffix': '$FAKE_ROLE_INJECTION_SUFFIX', 'error': 'ServiceFailure', 'exit': 254}}),
    ('term-during-put', 'success', {'signal': {'operation': 'put-role-policy', 'at': 'suffix', 'suffix': '$FAKE_ROLE_INJECTION_SUFFIX'}}),
    ('organizations-difference', 'success', {'organizations_difference': True}),
    ('delete-policy-fails', 'success', {'failure': {'operation': 'delete-role-policy', 'at': 1, 'error': 'ServiceFailure', 'exit': 254}}),
    ('term-after-delete-policy', 'success', {'signal': {'operation': 'delete-role-policy', 'at': 'suffix', 'suffix': '$FAKE_ROLE_INJECTION_SUFFIX'}}),
    ('verify-present', 'success', {'retain_role': True}),
)
def _flatten(envelope): return [{'schema_version': envelope['schema_version'], 'case_id': case['case_id'], 'document': envelope['document'], 'sid': envelope['sid'], **{key: value for key, value in case.items() if key != 'case_id'}} for case in envelope['cases']]
def _span(policy, index):
    decoder, spans = (json.JSONDecoder(), [])
    cursor = policy.index('[', policy.index('"Statement"')) + 1
    while policy[cursor] != ']':
        while policy[cursor].isspace() or policy[cursor] == ',': cursor += 1
        statement, end = decoder.raw_decode(policy, cursor)
        spans.append((cursor, end, statement['Sid']))
        cursor = end
    return spans[index]
def _match(start, end=None, source='PolicyInputList.1'): return {'SourcePolicyId': source, 'SourcePolicyType': 'IAM Policy', 'StartPosition': {'Line': 1, 'Column': start}, 'EndPosition': {'Line': 1, 'Column': end or start + 1}}
def _delimiter_match(policy, index, source='PolicyInputList.1'):
    start, end, _ = _span(policy, index)
    return _match((start if index == 0 else start - 1) + 1, end + 1, source)
def _policy(sid): return json.dumps({'Version': '2012-10-17', 'Statement': [{'Sid': sid, 'Effect': 'Allow', 'Action': 'iam:GetRole', 'Resource': '*'}]}, separators=(',', ':'))
def _context(taxonomy_path, projection_source):
    mapping = '{"Version":"2012-10-17","Statement":[{"Sid":"FixtureAllow","Effect":"Allow","Action":"s3:GetObject","Resource":"arn:aws:s3:::orbit-infra-79s5rw-good/*"},{"Sid":"DenyReadStateObjectsOutsideScope","Effect":"Deny","Action":"s3:GetObject","Resource":"arn:aws:s3:::orbit-infra-79s5rw-bad/*"}]}'
    per_pair_sid = '{"Version":"2012-10-17","Statement":[{"Sid":"DenyReadStateObjectsOutsideScope","Effect":"Allow","Action":["s3:GetObject","s3:GetObjectVersion"],"Resource":"*"},{"Sid":"FixtureAllow","Effect":"Allow","Action":"s3:GetObjectVersion","Resource":"*"}]}'
    real = '{"Version":"2012-10-17","Statement":[{"Action":["s3:GetObjectVersion","s3:GetObject"],"Effect":"Deny","NotResource":["arn:aws:s3:::orbit-infra-79s5rw-tfstate/envs/preview/*","arn:aws:s3:::orbit-infra-79s5rw-tfstate/bootstrap/*"],"Sid":"DenyReadStateObjectsOutsideScope"},{"Action":"s3:ListBucket","Effect":"Deny","NotResource":"arn:aws:s3:::orbit-infra-79s5rw-tfstate","Sid":"DenyListBucketOutsideScope"},{"Action":["s3:ListBucketVersions","s3:ListBucket"],"Condition":{"StringNotLike":{"s3:prefix":["envs/preview/*","bootstrap/*","envs/preview","bootstrap"]}},"Effect":"Deny","Resource":"arn:aws:s3:::orbit-infra-79s5rw-tfstate","Sid":"DenyListBucketOutsideScopePrefix"},{"Action":["s3:ListBucketVersions","s3:ListBucket"],"Condition":{"Null":{"s3:prefix":"true"}},"Effect":"Deny","Resource":"arn:aws:s3:::orbit-infra-79s5rw-tfstate","Sid":"DenyListBucketMissingPrefix"},{"Action":["ssm:GetParametersByPath","ssm:GetParameters","ssm:GetParameterHistory","ssm:GetParameter","secretsmanager:GetSecretValue","lambda:GetLayerVersion","lambda:GetFunctionConfiguration","lambda:GetFunction","kms:Decrypt"],"Effect":"Deny","Resource":"*","Sid":"DenySecretsAndParams"}]}'
    multiline = '\n'.join(('{', '  "Version": "2012-10-17",', '  "Statement": [', '    {"Sid":"FixtureAllow","Effect":"Allow","Action":"s3:GetObject","Resource":"*"},', '    {"Action":"s3:GetObject","Effect":"Deny","Resource":"*","Sid":"DenyReadStateObjectsOutsideScope"}', '  ]', '}'))
    scanner = json.dumps({'Version': '2012-10-17', 'Statement': [{'Sid': 'DenyReadStateObjectsOutsideScope', 'Effect': 'Allow', 'Action': 's3:GetObject', 'Resource': 'arn:aws:s3:::orbit-infra-79s5rw-delimiters/*', 'Condition': {'StringEquals': {'test:Value': 'literal { and } and [ stay inside this string'}}}, {'Sid': 'DenyListBucketOutsideScope', 'Effect': 'Allow', 'Action': 's3:GetObject', 'Resource': 'arn:aws:s3:::orbit-infra-79s5rw-escaped/*', 'Condition': {'StringEquals': {'test:Value': 'an escaped "quote } [" stays inside this string'}}}]}, separators=(',', ':'))
    ambiguous = '{"Version":"2012-10-17","Statement":[{"Sid":"EcrAuth","Effect":"Allow","Action":"ecr:GetAuthorizationToken","Resource":"*"},{"Sid":"Other__","Effect":"Allow","Action":"ecr:GetAuthorizationToken","Resource":"*"}]}'
    isolated = json.dumps({'Version': '2012-10-17', 'Statement': [{'Sid': 'LogsDescribeStarOnly', 'Effect': 'Allow', 'Action': 'logs:DescribeLogGroups', 'Resource': '*'}, {'Sid': 'LogsCreateWithTag', 'Effect': 'Allow', 'Action': ['logs:CreateLogGroup', 'logs:TagResource'], 'Resource': 'arn:aws:logs:*:000000000000:log-group:/orbit/79s5rw/*', 'Condition': {'StringEquals': {'aws:RequestTag/Project': 'orbit-infra'}}}]}, separators=(',', ':'))
    projection = json.loads(projection_source.read_text(encoding='utf-8'))
    real_plan = json.loads((taxonomy_path.parent.parent / 'iam-matrix' / 'base-plan.json').read_text(encoding='utf-8'))
    real_deployer = next((item['values']['policy'] for item in real_plan['planned_values']['root_module']['resources'] if item.get('address') == 'aws_iam_policy.deployer_data'))
    authorization_envelope = json.loads((taxonomy_path.parent / 'vectors' / 'aws_iam_policy.deployer_data__EnvDataBucketLifecycle.json').read_text(encoding='utf-8'))
    authorization_case = next((case for case in authorization_envelope['cases'] if case['case_id'] == 'case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching'))
    authorization_resources = [resource.replace('${SUFFIX}', '79s5rw') for resource in authorization_case['resource_arns']]
    role_authorization_decision = 'allowed'
    authorization_casefold_actions = [
        's3:deletebucketpublicaccessblock' if action == 's3:DeleteBucketPublicAccessBlock' else action
        for action in authorization_case['action_names']
    ]
    role_authorization_casefold_decision = 'allowed'
    if len(real) != 1163 or hashlib.sha256(real.encode()).hexdigest() != 'f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b': raise SystemExit('FAIL: real position policy fixture bytes changed')
    if len(real_deployer) != 5697 or len([_span(real_deployer, i) for i in range(18)]) != 18 or hashlib.sha256(real_deployer.encode()).hexdigest() != '19e3305cb5dc2c3cd62591306040bb56380ba7ae3fc9897bef91d14885413b92': raise SystemExit('FAIL: real deployer_data position fixture changed')
    if not _span(real_deployer, 7)[0] <= 1779 < _span(real_deployer, 7)[1] or _span(real_deployer, 7)[2] != 'ClickhouseSecretCreateWithTag': raise SystemExit('FAIL: real deployer_data offset 1779 owner changed')
    isolated_object = json.loads(isolated)
    isolated_object['Statement'] = isolated_object['Statement'][:1]
    duplicate_object = json.loads(isolated)
    duplicate_object['Statement'].append(deepcopy(duplicate_object['Statement'][1]))
    policy_map = {CORE_DOCUMENTS[0]: mapping, CORE_DOCUMENTS[2]: ambiguous, CORE_DOCUMENTS[6]: isolated, CORE_DOCUMENTS[1]: _policy('ReadStateObjects'), CORE_DOCUMENTS[3]: _policy('FixtureDeployerState'), CORE_DOCUMENTS[4]: _policy('FixtureDeployerEc2'), CORE_DOCUMENTS[5]: _policy('FixtureDeployerElbEcs'), CORE_DOCUMENTS[7]: _policy('FixtureDeployerIam'), CORE_DOCUMENTS[8]: _policy('FixtureDeployerGuard'), CORE_DOCUMENTS[9]: _policy('EcrAuth')}
    resources = [{'address': address, 'type': 'aws_iam_policy' if address.startswith('aws_iam_policy.') else 'aws_iam_role_policy', 'values': {'policy': policy_map[address]}} for address in CORE_DOCUMENTS]
    resources += [{'address': f'aws_iam_role.{short}', 'type': 'aws_iam_role', 'values': {'name': f"orbit-infra-79s5rw-{short.replace('_', '-')}"}} for short in ('plan_reader', 'deployer', 'publisher')]
    categories = json.loads(taxonomy_path.read_text(encoding='utf-8'))
    boundary_hash = hashlib.sha256(ambiguous.encode()).hexdigest()
    second_account = '111111' + '111111'
    second_account_policy = _policy('ReadStateObjects').replace(
        '"Resource":"*"',
        f'"Resource":"arn:aws:iam::{second_account}:role/example"',
    )
    ctx = {'taxonomy_path': taxonomy_path, 'categories': categories, 'projection_plan': projection, 'projection_policies': {r['address']: r['values']['policy'] for r in projection['planned_values']['root_module']['resources'] if isinstance(r.get('values'), dict) and isinstance(r['values'].get('policy'), str)}, 'synthetic_plan': {'planned_values': {'root_module': {'resources': resources}}}, 'policy_map': policy_map, 'second_account_policy': second_account_policy, 'per_pair_sid_policy': per_pair_sid, 'real_position_policy': real, 'multiline_position_policy': multiline, 'scanner_position_policy': scanner, 'isolated_missing_policy': json.dumps(isolated_object, separators=(',', ':')), 'isolated_duplicate_policy': json.dumps(duplicate_object, separators=(',', ':')), 'real_deployer_policy': real_deployer, 'role_authorization_decision': role_authorization_decision, 'role_authorization_casefold_decision': role_authorization_casefold_decision, 'excluded_boundary_policy_hashes': [{'sha256': boundary_hash}, {'sha256': '0' * 64}], 'excluded_boundary_boundary_hashes': [{'sha256': boundary_hash}]}
    ctx.update({'per_pair_sid_match0': _delimiter_match(per_pair_sid, 0), 'per_pair_sid_match1': _delimiter_match(per_pair_sid, 1)})
    ctx.update({'mapping_match0': _delimiter_match(mapping, 0), 'mapping_match1': _delimiter_match(mapping, 1), 'unmapped_match': _match(1), 'unknown_source_match': _delimiter_match(mapping, 1, 'UnknownPolicyLabel'), 'real_position_match': _match(38, 271)})
    first = ambiguous.index('{', ambiguous.index('[')) + 1
    second = ambiguous.index('{', first) + 1
    ctx.update({'ambiguous_cross_match': _match(first, second + 1), 'ambiguous_resolved_match': _match(first), 'ambiguous_policy': ambiguous})
    return ctx
def _case_value(ctx, payload, ordinal, key):
    matches = [row for row in ctx['categories'] if row['document'] == payload['document'] and row['category'] == 'simulator-decision' and (key == 'sid' or row.get('sid') == payload.get('sid'))]
    return matches[ordinal][key]
def _resolve(value, ctx, payload):
    if isinstance(value, tuple) and len(value) == 2 and (value[0] == '$ctx'): return deepcopy(ctx[value[1]])
    if isinstance(value, tuple) and len(value) == 2 and (value[0] in ('$case', '$sid')): return _case_value(ctx, payload, value[1], 'case_id' if value[0] == '$case' else 'sid')
    if isinstance(value, list): return [_resolve(item, ctx, payload) for item in value]
    if isinstance(value, dict): return {key: _resolve(item, ctx, payload) for key, item in value.items()}
    return value
def _apply(payload, edits, ctx):
    for edit in edits:
        operation, *arguments = edit
        if operation in ('set', 'delete'):
            path = arguments[0]
            parent = payload
            for key in path[:-1]: parent = parent[key]
            if operation == 'delete': del parent[path[-1]]
            else: parent[path[-1]] = _resolve(arguments[1], ctx, payload)
        elif operation == 'policy':
            resource = next((item for item in payload['planned_values']['root_module']['resources'] if item['address'] == arguments[0]))
            resource['values']['policy'] = _resolve(arguments[1], ctx, payload)
        elif operation == 'resource-value':
            resource = next((item for item in payload['planned_values']['root_module']['resources'] if item['address'] == arguments[0]))
            resource['values'][arguments[1]] = _resolve(arguments[2], ctx, payload)
        elif operation == 'duplicate-resource':
            resource = next((item for item in payload['planned_values']['root_module']['resources'] if item['address'] == arguments[0]))
            payload['planned_values']['root_module']['resources'].append(deepcopy(resource))
        elif operation == 'drop-resource': payload['planned_values']['root_module']['resources'] = [item for item in payload['planned_values']['root_module']['resources'] if item['address'] != arguments[0]]
        elif operation == 'statement-sid':
            resource = next((item for item in payload['planned_values']['root_module']['resources'] if item['address'] == arguments[0]))
            policy = json.loads(resource['values']['policy'])
            policy['Statement'][arguments[1]]['Sid'] = arguments[2]
            resource['values']['policy'] = json.dumps(policy, separators=(',', ':'))
        elif operation == 'action-level':
            result = payload['EvaluationResults'][0]
            resource = result.pop('ResourceSpecificResults')[0]
            result['MatchedStatements'] = resource['MatchedStatements']
        elif operation == 'all-resource-decisions':
            for result in payload['EvaluationResults']: result['ResourceSpecificResults'][0]['EvalResourceDecision'] = arguments[0]
        else: raise SystemExit(f'FAIL: unknown fixture edit {operation}')
    return payload
def _vector_source(ctx, name):
    if name == 'decision': return deepcopy(BASE_VECTOR)
    path = ctx['taxonomy_path'].parent / ('vectors/aws_iam_policy.deployer_data__EnvDataBucketLifecycle.json' if name == 'authorization-source' else 'valid-custom-isolated.json')
    vectors = _flatten(json.loads(path.read_text(encoding='utf-8')))
    if name == 'authorization-source': return next((v for v in vectors if v['case_id'] == 'case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching'))
    if len(vectors) != 1: raise SystemExit(f'FAIL: expected one synthetic case in {path}')
    return vectors[0]
def _evaluation(action, resource, decision, matches, template=None):
    result = {'EvalActionName': action, 'EvalResourceName': template or resource, 'EvalDecision': decision, 'ResourceSpecificResults': [{'EvalResourceName': resource, 'EvalResourceDecision': decision, 'MatchedStatements': matches, 'MissingContextValues': []}]}
    return {'EvaluationResults': [result]}
def _response_source(ctx, name, outputs):
    if name == 'mapping':
        good, bad = ('arn:aws:s3:::orbit-infra-79s5rw-good/example', 'arn:aws:s3:::orbit-infra-79s5rw-bad/example')
        result = {'EvalActionName': 's3:GetObject', 'EvalResourceName': 'arn:aws:s3:::${BucketName}/${KeyName}', 'EvalDecision': 'explicitDeny', 'MatchedStatements': [], 'MissingContextValues': [], 'OrganizationsDecisionDetail': {'AllowedByOrganizations': True}, 'ResourceSpecificResults': [{'EvalResourceName': good, 'EvalResourceDecision': 'allowed', 'MatchedStatements': [ctx['mapping_match0'], ctx['mapping_match1']], 'MissingContextValues': []}, {'EvalResourceName': bad, 'EvalResourceDecision': 'explicitDeny', 'MatchedStatements': [ctx['mapping_match0'], ctx['mapping_match1']], 'MissingContextValues': []}]}
        return {'EvaluationResults': [result], 'IsTruncated': False}
    if name.startswith('per-pair-sid-'):
        second_matches = [ctx['per_pair_sid_match1']]
        if name.endswith('restored'):
            second_matches.insert(0, ctx['per_pair_sid_match0'])
        return {'EvaluationResults': [
            _evaluation('s3:GetObject', '*', 'allowed', [ctx['per_pair_sid_match0']])['EvaluationResults'][0],
            _evaluation('s3:GetObjectVersion', '*', 'allowed', second_matches)['EvaluationResults'][0],
        ]}
    if name == 'real-position': return _evaluation('s3:GetObject', 'arn:aws:s3:::orbit-infra-79s5rw-tfstate/other/x', 'explicitDeny', [ctx['real_position_match']])
    if name.startswith('scanner-'):
        index = int(name[-1])
        resource = ('arn:aws:s3:::orbit-infra-79s5rw-delimiters/example', 'arn:aws:s3:::orbit-infra-79s5rw-escaped/example')[index]
        return _evaluation('s3:GetObject', resource, 'allowed', [_delimiter_match(ctx['scanner_position_policy'], index)])
    if name == 'deployer-position':
        resource = 'arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview'
        return {'EvaluationResults': [
            _evaluation(action, resource, 'allowed', [_match(1779, 2055)])['EvaluationResults'][0]
            for action in ('secretsmanager:CreateSecret', 'secretsmanager:TagResource')
        ]}
    if name == 'ambiguous': return _evaluation('ecr:GetAuthorizationToken', '*', 'allowed', [ctx['ambiguous_cross_match']])
    if name == 'duplicate': return _evaluation('secretsmanager:CreateSecret', 'arn:aws:secretsmanager:us-east-1:000000000000:secret:duplicate', 'allowed', [])
    if name == 'empty': return {}
    if name == 'isolated':
        vector = outputs['isolated-vectors/isolated.json']
        return {'EvaluationResults': [_evaluation(action, 'arn:aws:logs:us-east-1:000000000000:log-group:/orbit/79s5rw/example', 'implicitDeny', [], 'arn:aws:logs:*:${Account}:log-group:${LogGroupName}')['EvaluationResults'][0] for action in vector['action_names']]}
    if name == 'role-action-level': return {'EvaluationResults': [{'EvalActionName': 'iam:GetRole', 'EvalResourceName': '*', 'EvalDecision': 'allowed', 'MatchedStatements': [], 'MissingContextValues': []}]}
    return deepcopy(outputs[name])
def _record_report(ctx, outputs, specs):
    records = []
    for vector_path, policy_name, mode in specs:
        vector = outputs[vector_path]
        policy = None
        if policy_name == '@document': policy = ctx['projection_policies'][vector['document']]
        elif policy_name == 'real_deployer_policy': policy = ctx[policy_name]
        elif policy_name: policy = ctx['policy_map'].get(policy_name, ctx.get(policy_name))
        elif mode == 'custom-isolated':
            source_policy = json.loads(ctx['policy_map'][vector['document']])
            isolated_statement = next(
                statement for statement in source_policy['Statement']
                if statement.get('Sid') == vector['sid']
            )
            policy = json.dumps(
                {'Version': '2012-10-17', 'Statement': [isolated_statement]},
                separators=(',', ':'),
            )
        render = lambda value: value.replace('${ACCOUNT_ID}', '000000000000').replace('${SUFFIX}', '79s5rw')
        resources = [render(resource) for resource in vector.get('resource_arns', [])] or ['*']
        per_resource = vector['expect'].get('resource_decisions')
        rendered_resource_decisions = (
            {render(resource): decision for resource, decision in per_resource.items()}
            if isinstance(per_resource, dict) else None
        )
        decision_observed = rendered_resource_decisions or vector['expect']['decision']
        details = [
            {
                'action_name': action,
                'resource_arn': resource,
                'decision_observed': (
                    rendered_resource_decisions[resource]
                    if rendered_resource_decisions is not None
                    else vector['expect']['decision']
                ),
                'matched_statement_sources': [],
                'matched_sids': vector['expect']['matched_sid_required'],
            }
            for action in vector['action_names']
            for resource in resources
        ]
        records.append({
            'case_id': vector['case_id'],
            'decision_observed': decision_observed,
            'matched_sids': vector['expect']['matched_sid_required'],
            'details': details,
            'expect': vector['expect'],
            'pass': True,
            'mode': mode,
            'document_hashes_submitted': {
                'policy_input_list': [] if policy is None else [{'sha256': hashlib.sha256(policy.encode()).hexdigest()}],
                'permissions_boundary_policy_input_list': [],
            },
        })
    total = len(records)
    return {
        'recorded_at': '2026-09-10T00:00:00Z',
        'records': records,
        'summary': {
            'total': total, 'passed': total, 'failed': 0, 'runner_failures': 0
        },
    }

def _materialize(ctx, outputs, base, family):
    if isinstance(base, tuple) and base[0] == 'records': return _record_report(ctx, outputs, base[1])
    if base in outputs: return deepcopy(outputs[base])
    if family == 'plans': return deepcopy(ctx['synthetic_plan'] if base == 'synthetic' else ctx['projection_plan'])
    if family == 'vectors': return _vector_source(ctx, base)
    if family == 'responses': return _response_source(ctx, base, outputs)
    raise SystemExit(f'FAIL: unknown {family} fixture base {base}')
def _write(root, relative, payload, style):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    envelope = payload
    if style == 'vector':
        order = ('case_id', 'simulation_mode', 'assertion_kind', 'permissions_boundary_policy_input_list', 'action_names', 'resource_arns', 'context_entries', 'expect')
        case = {key: deepcopy(payload[key]) for key in order if key in payload}
        case.update({key: deepcopy(value) for key, value in payload.items() if key not in order and key not in ('schema_version', 'document', 'sid')})
        envelope = {'schema_version': payload['schema_version'], 'document': payload['document'], 'sid': payload['sid'], 'cases': [case]}
    options = {'indent': 2} if style in ('vector', 'pretty') else {}
    if style == 'sorted': options['sort_keys'] = True
    path.write_text(json.dumps(envelope, **options) + '\n', encoding='utf-8')
def _render_table(ctx, root, table, family, style, outputs):
    for relative, base, edits in table:
        payload = _apply(_materialize(ctx, outputs, base, family), edits, ctx)
        if family == 'vectors' and relative in ROLE_READINESS_CASES:
            payload.update(deepcopy(ROLE_READINESS_CASES[relative]))
        _write(root, relative, payload, style)
        outputs[relative] = payload
def _scenario_payloads():
    results = {}
    for name, base, overrides in ROLE_SCENARIOS:
        payload = deepcopy(results[base]) if base else {}
        for key, value in overrides.items():
            parent = payload
            parts = key.split('.')
            for part in parts[:-1]: parent = parent.setdefault(part, {})
            parent[parts[-1]] = value
        results[name] = payload
    return results
def _authorization_inputs(ctx, outputs, vector_path):
    vector = outputs[vector_path]
    aliases = {action.casefold() for action in S3_DIFFERENT_AUTHORIZATION_ACTIONS}
    actions = sorted(vector['action_names'])
    direct = [action for action in actions if action.casefold() not in aliases]
    aliased = [action for action in actions if action.casefold() in aliases]
    return {'actions': actions, 'resources': sorted((r.replace('${SUFFIX}', '79s5rw') for r in vector['resource_arns'])), 'accepted_action_groups': [actions, direct, aliased], 'required_action_groups': [direct, aliased]}
def _replace_account(value, account):
    if isinstance(value, str): return value.replace('000000000000', account)
    if isinstance(value, list): return [_replace_account(item, account) for item in value]
    if isinstance(value, dict): return {key: _replace_account(item, account) for key, item in value.items()}
    return value
def _custom_report_for_plan(report, plan, outputs):
    result = deepcopy(report)
    documents = {
        resource['address']: resource['values']['policy']
        for resource in plan['planned_values']['root_module']['resources']
        if isinstance(resource.get('values'), dict) and isinstance(resource['values'].get('policy'), str)
    }
    vectors = {
        payload['case_id']: payload
        for payload in outputs.values()
        if isinstance(payload, dict) and isinstance(payload.get('case_id'), str)
        and isinstance(payload.get('document'), str)
    }
    for record in result['records']:
        vector = vectors.get(record['case_id'])
        entries = record['document_hashes_submitted']['policy_input_list']
        if vector is not None and len(entries) == 1 and vector['document'] in documents:
            entries[0]['sha256'] = hashlib.sha256(documents[vector['document']].encode()).hexdigest()
    return result
def build_fixtures():
    taxonomy_path, root, projection_source = map(Path, sys.argv[1:4])
    ctx = _context(taxonomy_path, projection_source)
    outputs = {}
    for table, family, style in ((PLAN_FIXTURES, 'plans', 'pretty'), (VECTOR_FIXTURES, 'vectors', 'vector'), (RESPONSE_FIXTURES, 'responses', 'compact'), (CUSTOM_REPORT_FIXTURES, 'reports', 'pretty')): _render_table(ctx, root, table, family, style, outputs)
    _write(root, 'expected-authorization-split-inputs.json', _authorization_inputs(ctx, outputs, 'authorization-split-vectors/authorization-split.json'), 'sorted')
    _write(root, 'expected-authorization-casefold-inputs.json', _authorization_inputs(ctx, outputs, 'authorization-casefold-vectors/authorization-split.json'), 'sorted')
    bound_plan = _replace_account(outputs['plan.json'], '123456789012')
    _write(root, 'plan-account-bound.json', bound_plan, 'pretty')
    _write(root, 'plan-account-foreign.json', _replace_account(outputs['plan.json'], '222222222222'), 'pretty')
    _write(root, 'role-plan-account-custom-report.json', _custom_report_for_plan(outputs['role-custom-report.json'], bound_plan, outputs), 'pretty')
    _write(root, 'role-scenarios.json', _scenario_payloads(), 'pretty')
def _option(args, name):
    try:
        start = args.index(name) + 1
    except ValueError:
        return []
    end = start
    while end < len(args) and (not args[end].startswith('--')): end += 1
    return args[start:end]
def _counter(directory, name):
    path = directory / name
    value = int(path.read_text() if path.exists() else 0) + 1
    path.write_text(f'{value}\n', encoding='utf-8')
    return value
def _json_print(value): print(json.dumps(value, separators=(',', ':')))
def _scenario_matches(rule, operation, count, role_name):
    if not rule or rule.get('operation') != operation: return False
    at = rule.get('at')
    if isinstance(at, str) and at.startswith('$'): at = int(os.environ.get(at[1:]) or rule.get('default', 0))
    if at == 'suffix':
        suffix = os.environ.get(rule.get('suffix', '')[1:], '')
        return bool(suffix and role_name.endswith(suffix))
    return at == 'always' or at == count
def _fake_error(rule, operation):
    message = rule['error'] if rule.get('raw') else f"An error occurred ({rule['error']}) when calling the {''.join((part.title() for part in operation.split('-')))} operation"
    print(message, file=sys.stderr)
    raise SystemExit(rule['exit'])
def _fake_authorization_split(args, operation, response=None):
    actions, resources = (_option(args, '--action-names'), _option(args, '--resource-arns'))
    special = {action.casefold() for action in S3_DIFFERENT_AUTHORIZATION_ACTIONS}
    direct = sorted(action for action in actions if action.casefold() not in special)
    aliased = sorted(action for action in actions if action.casefold() in special)
    if direct and aliased:
        operation_name = ''.join((part.title() for part in operation.split('-')))
        print(f"An error occurred (InvalidInput) when calling the {operation_name} operation: Invalid Input Actions: [{','.join(direct)}] and [{','.join(aliased)}] require different authorization information.", file=sys.stderr)
        raise SystemExit(254)
    if response is not None:
        _json_print(response)
    else:
        _json_print({'EvaluationResults': [{'EvalActionName': action, 'EvalDecision': 'allowed', 'MatchedStatements': [], 'ResourceSpecificResults': [{'EvalResourceName': resource, 'EvalResourceDecision': 'allowed', 'MatchedStatements': [], 'MissingContextValues': []} for resource in resources]} for action in actions]})
def _validate_fake_context(args, scenario, operation):
    expected = scenario.get('expected_context_entries')
    if expected is None: return
    raw = _option(args, '--context-entries')
    try:
        submitted = json.loads(raw[0]) if len(raw) == 1 else []
    except json.JSONDecodeError:
        submitted = raw
    canonical = lambda entries: sorted(json.dumps(entry, sort_keys=True, separators=(',', ':')) for entry in entries) if isinstance(entries, list) else []
    if canonical(submitted) != canonical(expected):
        raise SystemExit(f"FAIL: fake {operation} context entries mismatch: expected {json.dumps(expected, sort_keys=True, separators=(',', ':'))}, submitted {json.dumps(submitted, sort_keys=True, separators=(',', ':'))}")
def _validate_fake_custom_inputs(args):
    expected_path = os.environ.get('FAKE_AWS_EXPECTED_INPUTS')
    if not expected_path: return
    expected = json.loads(Path(expected_path).read_text(encoding='utf-8'))
    for option, key, label in (('--action-names', 'actions', 'action names'), ('--resource-arns', 'resources', 'resource ARNs')):
        submitted = _option(args, option)
        accepted = expected.get('accepted_action_groups') if key == 'actions' else None
        valid = sorted(submitted) in accepted if accepted is not None else sorted(submitted) == expected[key]
        if not valid: raise SystemExit(f"FAIL: fake simulate-custom-policy {label} mismatch: expected {json.dumps(accepted if accepted is not None else expected[key], separators=(',', ':'))}, submitted {json.dumps(submitted, separators=(',', ':'))}")
def _load_state(path): return json.loads(path.read_text(encoding='utf-8'))
def _save_state(path, value): path.write_text(json.dumps(value, separators=(',', ':')) + '\n', encoding='utf-8')


def _fake_role_policy_response(options, state, force_implicit=False):
    actions = _option(options, '--action-names')
    resources = _option(options, '--resource-arns')
    policy = state['policy_document']
    statements = json.loads(policy)['Statement']
    if isinstance(statements, dict):
        statements = [statements]

    def matches_for(action, resource):
        matched = []
        effects = []
        for index, statement in enumerate(statements):
            patterns = statement.get('Action', [])
            if isinstance(patterns, str):
                patterns = [patterns]
            if not any(
                fnmatch.fnmatchcase(action.casefold(), pattern.casefold())
                for pattern in patterns
            ):
                continue
            resources_allowed = statement.get('Resource', '*')
            if isinstance(resources_allowed, str):
                resources_allowed = [resources_allowed]
            resources_excluded = statement.get('NotResource')
            if isinstance(resources_excluded, str):
                resources_excluded = [resources_excluded]
            if resources_excluded is not None:
                applies = not any(
                    fnmatch.fnmatchcase(resource, pattern)
                    for pattern in resources_excluded
                )
            else:
                applies = any(
                    fnmatch.fnmatchcase(resource, pattern)
                    for pattern in resources_allowed
                )
            if applies:
                matched.append(_delimiter_match(policy, index))
                effects.append(statement.get('Effect'))
        decision = 'implicitDeny' if force_implicit or not matched else (
            'explicitDeny' if 'Deny' in effects else 'allowed'
        )
        return decision, [] if force_implicit else matched

    results = []
    for action in actions:
        action_resources = resources or ['*']
        resolved = [matches_for(action, resource) for resource in action_resources]
        decisions = [decision for decision, _ in resolved]
        action_decision = (
            'explicitDeny' if 'explicitDeny' in decisions
            else 'allowed' if decisions and all(item == 'allowed' for item in decisions)
            else 'implicitDeny'
        )
        result = {
            'EvalActionName': action,
            'EvalDecision': action_decision,
            'MatchedStatements': resolved[0][1] if not resources else [],
            'MissingContextValues': [],
        }
        if resources:
            result['ResourceSpecificResults'] = [
                {
                    'EvalResourceName': resource,
                    'EvalResourceDecision': decision,
                    'MatchedStatements': matches,
                    'MissingContextValues': [],
                }
                for resource, (decision, matches) in zip(resources, resolved)
            ]
        results.append(result)
    return {'EvaluationResults': results}


def _fake_aws():
    scenario_file, *args = sys.argv[1:]
    call_dir, state_dir = (Path(os.environ['FAKE_AWS_CALL_DIR']), Path(os.environ['FAKE_ROLE_STATE_DIR']))
    call_dir.mkdir(parents=True, exist_ok=True)
    state_dir.mkdir(parents=True, exist_ok=True)
    call = _counter(call_dir, 'count')
    (call_dir / f'{call}.json').write_text(json.dumps(args) + '\n', encoding='utf-8')
    service, operation, *options = args
    scenario = json.loads(Path(scenario_file).read_text(encoding='utf-8'))[os.environ.get('FAKE_AWS_SCENARIO', 'success')]
    role_name = (_option(options, '--role-name') or [''])[0]
    if not role_name and _option(options, '--policy-source-arn'):
        role_name = _option(options, '--policy-source-arn')[0].rsplit('/', 1)[-1]
    if service == 'iam' and operation == 'simulate-custom-policy':
        _validate_fake_custom_inputs(args)
        _validate_fake_context(options, scenario, operation)
    counted = operation in ('simulate-custom-policy', 'create-role', 'delete-role-policy')
    count = _counter(call_dir, {'simulate-custom-policy': 'simulate-count', 'create-role': 'create-count', 'delete-role-policy': 'delete-policy-count'}.get(operation, operation + '-count')) if counted else 0
    if _scenario_matches(scenario.get('failure'), operation, count, role_name): _fake_error(scenario['failure'], operation)
    if (service, operation) == ('iam', 'simulate-custom-policy'):
        if scenario.get('custom') == 'authorization-split': _fake_authorization_split(options, operation)
        else: sys.stdout.write(Path(os.environ['FAKE_AWS_RESPONSE']).read_text(encoding='utf-8'))
    elif (service, operation) == ('sts', 'get-caller-identity'):
        account = os.environ.get('FAKE_ACCOUNT_ID', '000000000000')
        _json_print({'Account': account, 'Arn': f'arn:aws:iam::{account}:user/fixture-caller', 'UserId': 'fixture'})
    elif (service, operation) == ('iam', 'create-role'):
        tags = []
        for item in _option(options, '--tags'):
            key, separator, value = item.partition(',Value=')
            if not separator or not key.startswith('Key='): raise SystemExit(f'FAIL: fake create-role received an invalid tag: {item}')
            tags.append({'Key': key.removeprefix('Key='), 'Value': value})
        tamper = scenario.get('tamper_tag')
        if tamper and _scenario_matches({**tamper, 'at': 'suffix'}, operation, count, role_name):
            found = next((tag for tag in tags if tag['Key'] == tamper['key']), None)
            if found: found['Value'] = '1' * 32 if found['Value'] == '0' * 32 else '0' * 32
            else: tags.append({'Key': tamper['key'], 'Value': '0' * 32})
        _save_state(state_dir / f'{role_name}.json', {
            'tags': tags,
            'policy': False,
            'policy_document': None,
            'readback_attempts': 0,
            'probe_attempts': 0,
            'probe_complete': False,
        })
        _json_print({'Role': {'RoleName': role_name}})
    elif (service, operation) == ('iam', 'list-role-tags'):
        path = state_dir / f'{role_name}.json'
        if not path.exists(): _fake_error({'error': 'NoSuchEntity', 'exit': 254}, operation)
        tags = _load_state(path)['tags']
        tamper = scenario.get('tamper_tag')
        if tamper and tamper['operation'] == operation:
            for tag in tags:
                if tag['Key'] == tamper['key']: tag['Value'] = tamper['value']
        _json_print({'Tags': tags})
    elif (service, operation) == ('iam', 'put-role-policy'):
        path = state_dir / f'{role_name}.json'
        state = _load_state(path)
        state['policy'] = True
        state['policy_document'] = _option(options, '--policy-document')[0]
        state['readback_attempts'] = 0
        state['probe_attempts'] = 0
        state['probe_complete'] = False
        _save_state(path, state)
        _json_print({})
    elif (service, operation) == ('iam', 'get-role-policy'):
        path = state_dir / f'{role_name}.json'
        if not path.exists():
            _fake_error({'error': 'NoSuchEntity', 'exit': 254}, operation)
        state = _load_state(path)
        state['readback_attempts'] += 1
        _save_state(path, state)
        if not state['policy'] or state['readback_attempts'] <= scenario.get('propagation_delay_calls', 0):
            _fake_error({'error': 'NoSuchEntity', 'exit': 254}, operation)
        response = {'PolicyDocument': json.loads(state['policy_document'])}
        if _option(options, '--query') == ['PolicyDocument']:
            response = response['PolicyDocument']
        if _option(options, '--output') == ['json']:
            print(json.dumps(response, sort_keys=True, separators=(',', ':')))
        else:
            print(str(response))
    elif (service, operation) == ('iam', 'simulate-principal-policy'):
        if '--resource-arns' in options and not _option(options, '--resource-arns'):
            raise SystemExit('FAIL: fake simulate-principal-policy received --resource-arns with zero values')
        path = state_dir / f'{role_name}.json'
        state = _load_state(path)
        if not state.get('probe_complete'):
            state['probe_attempts'] += 1
            delayed = state['probe_attempts'] <= scenario.get(
                'readiness_delay_calls', scenario.get('propagation_delay_calls', 0)
            )
            if not delayed:
                state['probe_complete'] = True
            _save_state(path, state)
            _json_print(_fake_role_policy_response(options, state, delayed))
            if _scenario_matches(scenario.get('signal'), operation, count, role_name):
                os.kill(int(os.environ['IAM_SIM_LANE_PID']), signal.SIGTERM)
            return
        _validate_fake_context(options, scenario, operation)
        response = os.environ.get('FAKE_PRINCIPAL_RESPONSE')
        if scenario.get('custom') == 'authorization-split':
            _fake_authorization_split(
                options, operation, _fake_role_policy_response(options, state)
            )
        elif response: sys.stdout.write(Path(response).read_text(encoding='utf-8'))
        else:
            role_response = _fake_role_policy_response(options, state)
            if scenario.get('organizations_difference') and (not _option(options, '--policy-exclusion-list')):
                for result in role_response['EvaluationResults']:
                    result['EvalDecision'] = 'explicitDeny'
                    result['MatchedStatements'] = [{'SourcePolicyId': 'OrganizationsPolicy', 'SourcePolicyType': 'Organizations Policy'}]
                    for resource_result in result.get('ResourceSpecificResults', []):
                        resource_result['EvalResourceDecision'] = 'explicitDeny'
                        resource_result['MatchedStatements'] = result['MatchedStatements']
            _json_print(role_response)
    elif (service, operation) == ('iam', 'delete-role-policy'):
        path = state_dir / f'{role_name}.json'
        state = _load_state(path)
        if not state['policy']: _fake_error({'error': 'NoSuchEntity', 'exit': 254}, operation)
        state['policy'] = False
        _save_state(path, state)
        _json_print({})
    elif (service, operation) == ('iam', 'delete-role'):
        path = state_dir / f'{role_name}.json'
        state = _load_state(path)
        if state['policy']: _fake_error({'error': 'DeleteConflict', 'exit': 254}, operation)
        if not scenario.get('retain_role'): path.unlink()
        _json_print({})
    elif (service, operation) == ('iam', 'get-role'):
        if (state_dir / f'{role_name}.json').exists(): _json_print({'Role': {'RoleName': role_name}})
        else: _fake_error({'error': 'NoSuchEntity', 'exit': 254}, operation)
    else: raise SystemExit(f'unexpected fake AWS call: {service} {operation}')
    if _scenario_matches(scenario.get('signal'), operation, count, role_name): os.kill(int(os.environ['IAM_SIM_LANE_PID']), signal.SIGTERM)
def _table_counts():
    for name, table in (('plans', PLAN_FIXTURES), ('vector_envelopes', VECTOR_FIXTURES), ('simulator_responses', RESPONSE_FIXTURES), ('custom_reports', CUSTOM_REPORT_FIXTURES), ('role_scenarios', ROLE_SCENARIOS)): print(f'{name}={len(table)}')
def _command_assert_submitted_document_equals_plan():
    plan = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    call_paths = sorted(Path(sys.argv[2]).glob('*.json'))
    address = sys.argv[3]
    option = sys.argv[4]
    resources = plan['planned_values']['root_module']['resources']
    matches = [resource for resource in resources if resource.get('address') == address]
    if len(matches) != 1: raise SystemExit(f'FAIL: comparison plan has {len(matches)} resources for {address}')
    expected = matches[0]['values']['policy']
    simulate_calls = []
    for path in call_paths:
        args = json.loads(path.read_text(encoding='utf-8'))
        if args[:2] == ['iam', 'simulate-custom-policy']: simulate_calls.append(args)
    if len(simulate_calls) != 1: raise SystemExit(f'FAIL: comparison found {len(simulate_calls)} simulator calls')
    args = simulate_calls[0]
    if args.count(option) != 1: raise SystemExit(f'FAIL: comparison requires exactly one {option}')
    index = args.index(option) + 1
    submitted = []
    while index < len(args) and (not args[index].startswith('--')):
        submitted.append(args[index])
        index += 1
    if submitted != [expected]: raise SystemExit(f'FAIL: submitted {option} document differs from plan text for {address}')
def _command_mutate_submitted_document():
    option = sys.argv[2]
    for path in sorted(Path(sys.argv[1]).glob('*.json')):
        args = json.loads(path.read_text(encoding='utf-8'))
        if args[:2] != ['iam', 'simulate-custom-policy']: continue
        index = args.index(option) + 1
        args[index] += ' '
        path.write_text(json.dumps(args) + '\n', encoding='utf-8')
        break
    else: raise SystemExit('FAIL: no simulator call to mutate')
def _command_validate_real_report():
    def fail(message): raise SystemExit(f'FAIL: {message}')
    vector_dir = Path(sys.argv[1])
    report_path = Path(sys.argv[2])
    try:
        expected = [case['case_id'] for path in sorted(vector_dir.rglob('*.json')) for envelope in [json.loads(path.read_text(encoding='utf-8'))] for case in envelope['cases']]
        payload = json.loads(report_path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError, KeyError) as exc:
        fail(f'cannot read real-vector report inputs: {exc}')
    if len(expected) != 241: fail(f'real vector set has {len(expected)} case ids, expected 241')
    records = payload.get('records') if isinstance(payload, dict) else None
    if not isinstance(records, list): fail('report records must be an array')
    case_ids = [record.get('case_id') for record in records if isinstance(record, dict)]
    if len(case_ids) != len(records) or any((not isinstance(case_id, str) for case_id in case_ids)): fail('every report record must have a string case_id')
    counts = Counter(case_ids)
    repeated = sorted((case_id for case_id, count in counts.items() if count != 1))
    if repeated: fail(f'report repeats selected case_id: {repeated[0]}')
    missing = sorted(set(expected) - set(case_ids))
    if missing: fail(f'report omits selected case_id: {missing[0]}')
    unexpected = sorted(set(case_ids) - set(expected))
    if unexpected: fail(f'report contains unselected case_id: {unexpected[0]}')
    if payload.get('summary', {}).get('total') != 241: fail('report summary total must equal 241')
    by_id = {record['case_id']: record for record in records}
    shared_groups = set()
    shared_cases = set()
    for case_id, record in by_id.items():
        peers = record.get('shared_call_case_ids')
        if not isinstance(peers, list) or any((not isinstance(peer, str) for peer in peers)): fail(f'shared_call_case_ids must be a string array: {case_id}')
        if len(peers) != len(set(peers)) or case_id in peers: fail(f'shared_call_case_ids is not a unique peer set: {case_id}')
        if not peers: continue
        group = tuple(sorted([case_id, *peers]))
        shared_groups.add(group)
        shared_cases.update(group)
        for peer in peers:
            peer_record = by_id.get(peer)
            if peer_record is None: fail(f'shared-call peer is absent from report: {peer}')
            reciprocal = tuple(sorted([peer, *peer_record.get('shared_call_case_ids', [])]))
            if reciprocal != group: fail(f'shared-call peers are not reciprocal: {case_id} and {peer}')
    if len(shared_groups) != 8 or len(shared_cases) != 16: fail(f'shared-call census differs: {len(shared_groups)} batches and {len(shared_cases)} cases')
    print('PASS: real 241-vector report coverage (241 records, 8 shared-call batches, 16 shared cases)')
def _command_mutate_core_authorization_groups():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    old = '    for index, action_class in enumerate(normalized_classes, 1):\n'
    new = '    for index, action_class in enumerate((), 1):\n'
    if source.count(old) != 1: raise SystemExit('FAIL: shared-core authorization partition mutation anchor changed')
    Path(sys.argv[2]).write_text(source.replace(old, new, 1), encoding='utf-8')


def _command_mutate_core_sid_validation():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    strict = '        or not statement["Sid"].strip()\n'
    if source.count(strict) != 1: raise SystemExit('FAIL: shared-core Sid validation mutation anchor changed')
    Path(sys.argv[2]).write_text(source.replace(strict, '', 1), encoding='utf-8')


def _command_mutate_plan_guard():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    repo_root = sys.argv[3]
    lane = sys.argv[4]
    guard = sys.argv[5]
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    anchors = {
        ('runner', 'resources-array'): '    if not isinstance(resources, list):\n        fail("plan planned_values.root_module.resources must be an array")',
        ('runner', 'exactly-one-document'): '        if len(matches) != 1:\n            fail(f"plan must contain exactly one {address}, found {len(matches)}")',
        ('runner', 'nonempty-policy'): '        if not isinstance(policy, str) or not policy:\n            fail(f"plan policy document is null, unknown, or empty: {address}")',
        ('runner', 'role-name'): '    if not isinstance(role_name, str):\n        fail("plan reader role name is null or unknown")',
        ('runner', 'suffix'): '    if suffix_match is None or not suffix_match.group(1):\n        fail(f"cannot derive SUFFIX from plan reader role name: {role_name}")',
        ('runner', 'account-id-uniqueness'): '    if len(account_ids) > 1:\n        fail(f"plan policy documents contain multiple account ids: {account_ids}")',
        ('role-lane', 'resources-array'): 'if not isinstance(resources, list):\n    fail("plan resources must be an array")',
        ('role-lane', 'exactly-one-document'): '    if len(matches) != 1:\n        fail(f"plan must contain exactly one {address}, found {len(matches)}")',
        ('role-lane', 'nonempty-policy'): '    if not isinstance(policy, str) or not policy:\n        fail(f"plan policy document is null, unknown, or empty: {address}")',
        ('role-lane', 'role-name'): 'if not isinstance(reader_name, str):\n    fail("plan reader role name is null or unknown")',
        ('role-lane', 'suffix'): 'if suffix_match is None:\n    fail(f"cannot derive SUFFIX from plan reader role name: {reader_name}")',
        ('role-lane', 'account-id-uniqueness'): 'if len(plan_account_ids) > 1:\n    fail(f"plan policy documents contain multiple account ids: {plan_account_ids}")',
    }
    try:
        anchor = anchors[(lane, guard)]
    except KeyError as exc:
        raise SystemExit(f'FAIL: unknown plan guard mutation: {lane}:{guard}') from exc
    if source.count(root_line) != 1 or source.count(anchor) != 1:
        raise SystemExit(f'FAIL: {lane} {guard} plan-guard mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(repo_root)}', 1)
    mutant = re.sub(r'(?m)^(\s*)if [^\n]+:', r'\1if False:', anchor, count=1)
    source = source.replace(anchor, mutant, 1)
    destination.write_text(source, encoding='utf-8')
    destination.chmod(0o755)


def _command_mutate_evidence_role_check():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    mutation = sys.argv[3]
    per_pair_strict = (
        '            if not set(required) <= matched_set '
        'or set(forbidden) & matched_set:'
    )
    aggregate_strict = (
        '    return set(required) <= matched_set '
        'and not (set(forbidden) & matched_set)'
    )
    replacements = {
        'forbidden': (
            '            if not set(required) <= matched_set:',
            '    return set(required) <= matched_set',
        ),
        'required': (
            '            if set(forbidden) & matched_set:',
            '    return not (set(forbidden) & matched_set)',
        ),
    }
    if mutation not in replacements:
        raise SystemExit(f'FAIL: unknown Evidence role-check mutation: {mutation}')
    if source.count(per_pair_strict) != 1 or source.count(aggregate_strict) != 1:
        raise SystemExit('FAIL: Evidence role-check mutation anchor changed')
    per_pair_replacement, aggregate_replacement = replacements[mutation]
    source = source.replace(per_pair_strict, per_pair_replacement, 1)
    source = source.replace(aggregate_strict, aggregate_replacement, 1)
    destination.write_text(source, encoding='utf-8')


def _command_validate_role_authorization_split():
    call_paths = sorted(Path(sys.argv[1]).glob('*.json'), key=lambda item: int(item.stem))
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    last_put = max(
        index for index, args in enumerate(calls)
        if args[:2] == ['iam', 'put-role-policy']
    )
    envelope = json.loads(Path(sys.argv[3]).read_text(encoding='utf-8'))
    vector = _flatten(envelope)[0]
    action_groups = _authorization_action_groups(vector['action_names'])
    simulations = [
        args for index, args in enumerate(calls)
        if index > last_put
        and args[:2] == ['iam', 'simulate-principal-policy']
        and _option(args, '--action-names') in action_groups
    ]
    if len(action_groups) != 2 or len(simulations) != 2 * len(action_groups):
        raise SystemExit('FAIL: role authorization partition requires exactly two calls per principal run')
    resources = sorted(resource.replace('${SUFFIX}', '79s5rw') for resource in vector['resource_arns'])
    expected_calls = ([(group, True) for group in action_groups] + [(group, False) for group in action_groups])
    exclusion = '{"PolicyType":"scp"}'
    for call, (expected_actions, excluded) in zip(simulations, expected_calls):
        if _option(call, '--action-names') != expected_actions:
            raise SystemExit('FAIL: role authorization partition submitted the wrong action groups')
        if sorted(_option(call, '--resource-arns')) != resources:
            raise SystemExit('FAIL: role authorization partition changed the submitted resources')
        exclusions = _option(call, '--policy-exclusion-list')
        if exclusions != ([exclusion] if excluded else []):
            raise SystemExit('FAIL: role authorization partition changed the principal run shape')
    expected_decision = 'allowed'
    payload = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
    records = payload.get('records', [])
    if len(records) != 1:
        raise SystemExit('FAIL: role authorization partition report requires one record')
    record = records[0]
    if record.get('scp_excluded', {}).get('decision_observed') != expected_decision or record.get('default', {}).get('decision_observed') != expected_decision:
        raise SystemExit('FAIL: role authorization partition did not combine every per-action decision')
    if record.get('comparison') != 'agreement' or record.get('pass') is not True:
        raise SystemExit('FAIL: role authorization partition did not preserve the case result')


def _command_mutate_shared_core_overlap():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    overlap_line = '            if start < end and start < span_end and span_start < end:'
    strict_line = '            if span_start <= start < span_end and span_start <= end < span_end:'
    if source.count(overlap_line) != 1: raise SystemExit('FAIL: shared-core unique-overlap mutation anchor changed')
    Path(sys.argv[2]).write_text(source.replace(overlap_line, strict_line), encoding='utf-8')
def _command_mutate_shared_core_scanner():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    scan_line = '                        statement, end = decoder.raw_decode(policy, start)'
    if source.count(scan_line) != 1: raise SystemExit('FAIL: shared-core scanner mutation anchor changed')
    if sys.argv[3] == 'string-delimiters': mutation = '                        end = policy.index("}", start) + 1\n                        statement = json.loads(policy[start:end])'
    else: mutation = '                        mutated_policy = policy[:start] + policy[start:].replace(chr(92) + chr(34), chr(34), 1)\n                        statement, end = decoder.raw_decode(mutated_policy, start)'
    Path(sys.argv[2]).write_text(source.replace(scan_line, mutation), encoding='utf-8')
def _command_mutate_role_context_entries():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    context_line = "  [ \"$context\" = '[]' ] || CASE_CONTEXT_ARGS=(--context-entries \"$context\" --output json)"
    if source.count(root_line) != 1 or source.count(context_line) != 1: raise SystemExit('FAIL: role context-entry mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}', 1)
    source = source.replace(context_line, '  : # context entries deliberately dropped', 1)
    destination.write_text(source, encoding='utf-8')
    destination.chmod(0o755)
def _command_mutate_custom_context_entries():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    context_line = '        if first["context"]:'
    if source.count(root_line) != 1 or source.count(context_line) != 1: raise SystemExit('FAIL: custom context-entry mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}', 1)
    source = source.replace(context_line, '        if False:  # context entries deliberately dropped', 1)
    destination.write_text(source, encoding='utf-8')
    destination.chmod(0o755)
def _command_validate_role_plan_account_redaction():
    report_path = Path(sys.argv[1])
    account = sys.argv[2]
    expected_marker = sys.argv[3] == 'true'
    placeholder = '000000000000'
    serialized = report_path.read_text(encoding='utf-8')
    without_hashes = re.sub('(?<![0-9A-Fa-f])[0-9A-Fa-f]{64}(?![0-9A-Fa-f])', '', serialized)
    if account != placeholder and account in without_hashes:
        raise SystemExit(f'FAIL: role report contains unredacted plan account id: {account}')
    payload = json.loads(serialized)
    if payload.get('plan_account') != placeholder:
        raise SystemExit('FAIL: role report plan_account is not the placeholder')
    if payload.get('plan_account_redacted') is not expected_marker:
        raise SystemExit(f'FAIL: role report plan_account_redacted is not {str(expected_marker).lower()}')
def _command_validate_role_account_redaction():
    report_path = Path(sys.argv[1])
    call_paths = sorted(Path(sys.argv[2]).glob('*.json'), key=lambda path: int(path.stem))
    account = sys.argv[3]
    placeholder = '000000000000'
    serialized = report_path.read_text(encoding='utf-8')
    without_hashes = re.sub('(?<![0-9A-Fa-f])[0-9A-Fa-f]{64}(?![0-9A-Fa-f])', '', serialized)
    account_runs = set(re.findall('(?<![0-9])[0-9]{12}(?![0-9])', without_hashes))
    unexpected = sorted(account_runs - {placeholder})
    if unexpected: raise SystemExit(f'FAIL: role report contains unredacted 12-digit account id: {unexpected[0]}')
    payload = json.loads(serialized)
    if payload.get('redaction_applied') is not True: raise SystemExit('FAIL: role report lacks the shared redaction marker')
    if payload.get('account') != placeholder or payload.get('account_redacted') is not True: raise SystemExit('FAIL: role report lacks the placeholder account and account_redacted marker')
    if payload.get('ownership_nonce') != '<redacted>' or payload.get('ownership_nonce_redacted') is not True: raise SystemExit('FAIL: role report lacks the redacted ownership nonce marker')
    redacted_principal = 'arn:aws:iam::000000000000:<redacted-principal>'
    report_trust = json.loads(payload.get('projection', {}).get('assume_role_policy', '{}'))
    report_principal = report_trust.get('Statement', [{}])[0].get('Principal', {}).get('AWS')
    if report_principal != redacted_principal: raise SystemExit('FAIL: role report does not fully redact the caller principal ARN')
    if 'fixture-caller' in serialized: raise SystemExit('FAIL: role report contains the caller principal name')
    if not payload.get('manual_cleanup'): raise SystemExit('FAIL: role report account-redaction fixture lacks a manual-cleanup note')
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    creates = [call for call in calls if call[:2] == ['iam', 'create-role']]
    simulations = [call for call in calls if call[:2] == ['iam', 'simulate-principal-policy']]
    if not creates or not simulations: raise SystemExit('FAIL: role account-redaction fixture lacks live-call records')
    for call in creates:
        role_name = call[call.index('--role-name') + 1]
        trust_policy = call[call.index('--assume-role-policy-document') + 1]
        expected_trust = f'arn:aws:iam::{account}:user/fixture-caller'
        if account not in role_name or json.loads(trust_policy)['Statement'][0]['Principal']['AWS'] != expected_trust: raise SystemExit('FAIL: create-role call did not trust exactly the invoking identity')
        tag_index = call.index('--tags') + 1
        nonce_tag = next((tag for tag in call[tag_index:] if tag.startswith('Key=OrbitIamSimulationNonce,Value=')), None)
        if nonce_tag is None: raise SystemExit('FAIL: create-role call lacks the ownership nonce')
        nonce = nonce_tag.partition(',Value=')[2]
        if nonce in serialized: raise SystemExit('FAIL: role report contains an ownership nonce')
    for call in simulations:
        source_arn = call[call.index('--policy-source-arn') + 1]
        if not source_arn.startswith(f'arn:aws:iam::{account}:role/') or account not in source_arn: raise SystemExit('FAIL: simulate-principal-policy call did not retain the real account id')
def _command_validate_role_creation_failure():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    call_paths = sorted(Path(sys.argv[2]).glob('*.json'), key=lambda path: int(path.stem))
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    expected_role_count = int(sys.argv[3])
    failure_index = int(sys.argv[4])
    created_count = int(sys.argv[5])
    roles = payload.get('projection', {}).get('roles', [])
    if len(roles) != expected_role_count: raise SystemExit(f'FAIL: role failure fixture requires {expected_role_count} projections, found {len(roles)}')
    if not 1 <= created_count <= failure_index <= expected_role_count: raise SystemExit('FAIL: role failure fixture has invalid creation boundaries')
    if expected_role_count == 8:
        failed_role = roles[failure_index - 1]
        if failed_role.get('role_kind') != 'deployer' or not failed_role.get('name', '').endswith('-deployer-p4'): raise SystemExit('FAIL: eight-role failure must be injected at deployer p4')
    role_names = [role['name'] for role in roles]
    def operation_calls(operation): return [call for call in calls if call[:2] == ['iam', operation]]
    def call_role_name(call): return call[call.index('--role-name') + 1]
    creates = [call_role_name(call) for call in operation_calls('create-role')]
    deletes = [call_role_name(call) for call in operation_calls('delete-role')]
    gets = [call_role_name(call) for call in operation_calls('get-role')]
    if creates != role_names[:failure_index]: raise SystemExit('FAIL: role failure fixture created a role after the injected failure')
    if deletes != list(reversed(role_names[:created_count])): raise SystemExit('FAIL: role failure cleanup did not delete every created role in reverse order')
    if gets != role_names[:failure_index]: raise SystemExit('FAIL: role failure cleanup did not verify every attempted role absent')
    later_roles = set(role_names[failure_index:])
    for call in calls:
        if '--role-name' in call and call_role_name(call) in later_roles: raise SystemExit('FAIL: role failure fixture touched a role after the injected failure')
def _command_role_wrong_hash_expected_line():
    plan = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    vectors = [{'schema_version': envelope['schema_version'], 'document': envelope['document'], 'sid': envelope['sid'], **case} for path in Path(sys.argv[2]).glob('*.json') for envelope in [json.loads(path.read_text(encoding='utf-8'))] for case in envelope['cases']]
    report = json.loads(Path(sys.argv[3]).read_text(encoding='utf-8'))
    policies = {resource['address']: resource['values']['policy'] for resource in plan['planned_values']['root_module']['resources'] if isinstance(resource.get('values'), dict) and isinstance(resource['values'].get('policy'), str)}
    for vector in vectors:
        record = next((item for item in report['records'] if item['case_id'] == vector['case_id']))
        observed = record['document_hashes_submitted']['policy_input_list'][0]['sha256']
        expected = hashlib.sha256(policies[vector['document']].encode('utf-8')).hexdigest()
        if observed != expected:
            print(f"FAIL: custom report policy hash mismatch for {vector['case_id']}: report={observed} plan={expected}")
            break
    else: raise SystemExit('FAIL: wrong-hash fixture contains no mismatch')
def _command_validate_role_cleanup_race():
    report_path = Path(sys.argv[1])
    call_paths = sorted(Path(sys.argv[2]).glob('*.json'), key=lambda path: int(path.stem))
    role_state = Path(sys.argv[3])
    scenario = sys.argv[4]
    if not report_path.is_file(): raise SystemExit('FAIL: cleanup race did not write its report')
    payload = json.loads(report_path.read_text(encoding='utf-8'))
    roles = payload.get('projection', {}).get('roles', [])
    if len(roles) != 8: raise SystemExit(f'FAIL: cleanup race requires eight roles, found {len(roles)}')
    role_names = [role['name'] for role in roles]
    target = next((role['name'] for role in roles if role.get('name', '').endswith('-deployer-p4')), None)
    if target is None: raise SystemExit('FAIL: cleanup race lacks the deployer-p4 injection role')
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    def operation_names(operation): return [call[call.index('--role-name') + 1] for call in calls if call[:2] == ['iam', operation]]
    puts = operation_names('put-role-policy')
    delete_policies = operation_names('delete-role-policy')
    delete_roles = operation_names('delete-role')
    gets = operation_names('get-role')
    if scenario in {'term-during-put', 'put-policy-fails'}:
        expected_puts = role_names[:5]
        expected_delete_policies = list(reversed(role_names[:5]))
        expected_records = 0
        if puts != expected_puts or puts[-1] != target: raise SystemExit('FAIL: cleanup race was not injected while loading deployer-p4')
    elif scenario == 'term-after-delete-policy':
        expected_puts = role_names
        expected_delete_policies = list(reversed(role_names))
        expected_records = 9
        if target not in delete_policies: raise SystemExit('FAIL: cleanup race was not injected after deployer-p4 policy deletion')
    else: raise SystemExit(f'FAIL: unknown cleanup-race scenario: {scenario}')
    if delete_policies != expected_delete_policies: raise SystemExit('FAIL: cleanup race did not attempt every marked policy in reverse order')
    if delete_roles != list(reversed(role_names)): raise SystemExit('FAIL: cleanup race did not delete every role in reverse order')
    if gets != role_names: raise SystemExit('FAIL: cleanup race did not verify NoSuchEntity for every role')
    if any(role_state.glob('*.json')): raise SystemExit('FAIL: cleanup race left role state behind')
    if len(payload.get('records', [])) != expected_records: raise SystemExit('FAIL: cleanup race report has the wrong completed-record count')
def _command_validate_role_nonce_tamper():
    report_path = Path(sys.argv[1])
    call_paths = sorted(Path(sys.argv[2]).glob('*.json'), key=lambda path: int(path.stem))
    role_state = Path(sys.argv[3])
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    puts = sum((call[:2] == ['iam', 'put-role-policy'] for call in calls))
    delete_policies = sum((call[:2] == ['iam', 'delete-role-policy'] for call in calls))
    delete_roles = sum((call[:2] == ['iam', 'delete-role'] for call in calls))
    if puts or delete_policies or delete_roles: raise SystemExit(f'FAIL: nonce tamper reached policy or role mutations: put={puts} delete-policy={delete_policies} delete-role={delete_roles}')
    creates = [call for call in calls if call[:2] == ['iam', 'create-role']]
    if len(creates) != 8: raise SystemExit(f'FAIL: nonce tamper requires eight create calls, found {len(creates)}')
    nonces = set()
    for call in creates:
        index = call.index('--tags') + 1
        raw_tags = []
        while index < len(call) and (not call[index].startswith('--')):
            raw_tags.append(call[index])
            index += 1
        tags = {}
        for raw_tag in raw_tags:
            key_part, separator, value = raw_tag.partition(',Value=')
            if not separator or not key_part.startswith('Key='): raise SystemExit('FAIL: nonce tamper create call has an invalid tag')
            tags[key_part.removeprefix('Key=')] = value
        if set(tags) != {'OrbitIamSimulationRun', 'OrbitIamSimulationNonce'}: raise SystemExit('FAIL: nonce tamper create call lacks both ownership tags')
        nonce = tags['OrbitIamSimulationNonce']
        if re.fullmatch('[0-9a-f]{32}', nonce) is None: raise SystemExit('FAIL: ownership nonce is not 32 lowercase hex characters')
        nonces.add(nonce)
    if len(nonces) != 1: raise SystemExit('FAIL: one invocation did not use one ownership nonce')
    state_paths = list(role_state.glob('*.json'))
    if len(state_paths) != 8: raise SystemExit('FAIL: nonce tamper refusal did not preserve all eight roles for manual cleanup')
    target_path = next((path for path in state_paths if path.stem.endswith('-deployer-p4')), None)
    if target_path is None: raise SystemExit('FAIL: nonce tamper state lacks deployer-p4')
    target_tags = {tag['Key']: tag['Value'] for tag in json.loads(target_path.read_text(encoding='utf-8'))['tags']}
    if target_tags.get('OrbitIamSimulationRun') != 'fixture-run': raise SystemExit('FAIL: nonce tamper changed the run-id tag')
    if target_tags.get('OrbitIamSimulationNonce') in nonces: raise SystemExit("FAIL: nonce tamper did not change deployer-p4's nonce")
    if not report_path.is_file(): raise SystemExit('FAIL: nonce tamper did not write its report')
    serialized = report_path.read_text(encoding='utf-8')
    for nonce in nonces | {target_tags.get('OrbitIamSimulationNonce')}:
        if nonce and nonce in serialized: raise SystemExit('FAIL: role report contains an ownership nonce')
    payload = json.loads(serialized)
    if not any(('ownership tag mismatch' in note for note in payload.get('manual_cleanup', []))): raise SystemExit('FAIL: nonce tamper report does not name the ownership mismatch')
def _command_mutate_role_report_redaction():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    redaction_block = 'redactions.append((role_plan["account_id"], placeholder_account))\nif role_plan["vector_account_id"] != placeholder_account:\n    redactions.append((role_plan["vector_account_id"], placeholder_account))\n'
    if source.count(root_line) != 1 or source.count(redaction_block) != 1: raise SystemExit('FAIL: role report-redaction mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}')
    source = source.replace(redaction_block, '')
    destination.write_text(source, encoding='utf-8')
def _command_mutate_role_trust_root():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    principal_line = 'principal = caller_arn'
    if source.count(root_line) != 1 or source.count(principal_line) != 1:
        raise SystemExit('FAIL: role root-trust mutation anchors changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}', 1)
    source = source.replace(
        principal_line,
        'principal = f"arn:aws:iam::{caller_arn.split(chr(58))[4]}:root"',
        1,
    )
    destination.write_text(source, encoding='utf-8')


def _command_mutate_role_principal_redaction():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    redaction_line = 'redactions = [(role_plan["caller_arn"], redacted_principal)]'
    if source.count(root_line) != 1 or source.count(redaction_line) != 1:
        raise SystemExit('FAIL: role principal-redaction mutation anchors changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}', 1)
    source = source.replace(redaction_line, 'redactions = []', 1)
    destination.write_text(source, encoding='utf-8')


def _command_validate_role_trust_calls():
    call_paths = sorted(Path(sys.argv[1]).glob('*.json'), key=lambda item: int(item.stem))
    account = sys.argv[2]
    expected = f'arn:aws:iam::{account}:user/fixture-caller'
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    creates = [call for call in calls if call[:2] == ['iam', 'create-role']]
    if not creates: raise SystemExit('FAIL: exact-caller trust fixture has no create-role calls')
    for call in creates:
        policy = json.loads(call[call.index('--assume-role-policy-document') + 1])
        if policy.get('Statement', [{}])[0].get('Principal') != {'AWS': expected}:
            raise SystemExit('FAIL: create-role trust does not name exactly the invoking identity')
    print('PASS: every create-role trust names exactly the invoking identity')


def _command_validate_role_principal_redaction():
    serialized = Path(sys.argv[1]).read_text(encoding='utf-8')
    payload = json.loads(serialized)
    expected = 'arn:aws:iam::000000000000:<redacted-principal>'
    policy = json.loads(payload.get('projection', {}).get('assume_role_policy', '{}'))
    if policy.get('Statement', [{}])[0].get('Principal') != {'AWS': expected}:
        raise SystemExit('FAIL: role report does not fully redact the caller principal ARN')
    if 'fixture-caller' in serialized:
        raise SystemExit('FAIL: role report contains the caller principal name')
    print('PASS: role report fully redacts the caller principal ARN')


def _command_validate_role_per_pair():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    records = payload.get('records', [])
    if len(records) != 1:
        raise SystemExit('FAIL: role per-pair fixture must contain one record')
    record = records[0]
    if record.get('pass') is not True:
        errors = record.get('errors', [])
        detail = errors[0] if errors else 'role record did not pass'
        raise SystemExit(f'FAIL: role comparison {detail}')
    details = record.get('scp_excluded', {}).get('details', [])
    if len(details) != 2:
        raise SystemExit('FAIL: role comparison did not retain two per-pair details')
    print('PASS: role comparison validates every action/resource pair')


def _command_mutate_role_nonce_check():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    complete_check = '[{Key:$run_key,Value:$run_value},{Key:$nonce_key,Value:$nonce_value}]'
    run_only_check = '[{Key:$run_key,Value:$run_value}]'
    if source.count(root_line) != 1 or source.count(complete_check) != 1: raise SystemExit('FAIL: role nonce-check mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}')
    source = source.replace(complete_check, run_only_check)
    destination.write_text(source, encoding='utf-8')
def _command_mutate_role_cleanup_high_indices():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    cleanup_loop = '  for ((index = role_count - 1; index >= 0; index--)); do\n    role_name="$(jq -r ".roles[$index].name" "$role_plan")"\n'
    mutated_loop = '  for ((index = role_count > 3 ? 2 : role_count - 1; index >= 0; index--)); do\n    role_name="$(jq -r ".roles[$index].name" "$role_plan")"\n'
    if source.count(root_line) != 1 or source.count(cleanup_loop) != 1: raise SystemExit('FAIL: role high-index cleanup mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}')
    source = source.replace(cleanup_loop, mutated_loop)
    destination.write_text(source, encoding='utf-8')
def _command_validate_role_selection_report():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    records = payload.get('records', [])
    exclusions = payload.get('exclusions', [])
    summary = payload.get('summary', {})
    reason = 'isolated single-statement simulation has no principal equivalent'
    boundary_case = 'case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:outside-boundary'
    boundary_reason = 'document is not an identity-role binding'
    if len(records) != 3: raise SystemExit(f'FAIL: role selection requires three custom-vector records, found {len(records)}')
    if any((record.get('mode') != 'principal' for record in records)): raise SystemExit('FAIL: role selection did not execute every custom vector through principal simulation')
    isolated = [entry for entry in exclusions if entry.get('reason') == reason]
    if len(isolated) != 1 or not isolated[0].get('case_id'): raise SystemExit('FAIL: role selection must record one custom-isolated exclusion with its reason')
    boundary = [entry for entry in exclusions if entry.get('case_id') == boundary_case and entry.get('reason') == boundary_reason]
    if len(boundary) != 1: raise SystemExit('FAIL: role selection must record the task-boundary custom case exclusion with its reason')
    if summary.get('cases_selected') != 3: raise SystemExit('FAIL: role selection summary must count three selected cases')
    if summary.get('cases_excluded_by_reason', {}).get(reason) != 1: raise SystemExit('FAIL: role selection summary must count the custom-isolated exclusion reason')
    if summary.get('cases_excluded_by_reason', {}).get(boundary_reason) != 1: raise SystemExit('FAIL: role selection summary must count the task-boundary exclusion reason')
def _command_mutate_role_selection_report():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    reason = 'isolated single-statement simulation has no principal equivalent'
    entry = next((item for item in payload['exclusions'] if item.get('reason') == reason))
    entry['reason'] = 'mutated generic exclusion'
    Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
def _command_mutate_role_only_selection():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    selection = '    selected = [vector for vector in vectors if vector["case_id"] == only]'
    if source.count(root_line) != 1 or source.count(selection) != 1: raise SystemExit('FAIL: role --only selection mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}', 1)
    destination.write_text(source.replace(selection, '    selected = []', 1), encoding='utf-8')
    destination.chmod(493)
def _command_mutate_role_custom_preflight_scope():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    scoped_loop = '    for vector in supported:'
    if source.count(root_line) != 1 or source.count(scoped_loop) != 1: raise SystemExit('FAIL: role custom-report preflight-scope mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}', 1)
    destination.write_text(source.replace(scoped_loop, '    for vector in vectors:', 1), encoding='utf-8')
    destination.chmod(493)
def _command_validate_role_projection_report():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    vectors_in_order = [{'schema_version': envelope['schema_version'], 'document': envelope['document'], 'sid': envelope['sid'], **case} for path in sorted(Path(sys.argv[2]).glob('*.json')) for envelope in [json.loads(path.read_text(encoding='utf-8'))] for case in envelope['cases']]
    vectors = {vector['case_id']: vector for vector in vectors_in_order}
    if len(vectors) != len(vectors_in_order): raise SystemExit('FAIL: role projection vectors repeat a case id')
    plan = json.loads(Path(sys.argv[3]).read_text(encoding='utf-8'))
    policies = {resource['address']: resource['values']['policy'] for resource in plan['planned_values']['root_module']['resources'] if isinstance(resource.get('values'), dict) and isinstance(resource['values'].get('policy'), str)}
    role_documents = (('plan-reader', ['aws_iam_role_policy.plan_reader_deny', 'aws_iam_role_policy.plan_reader_state']), ('deployer', ['aws_iam_policy.deployer_data', 'aws_iam_policy.deployer_ec2', 'aws_iam_policy.deployer_elb_ecs', 'aws_iam_policy.deployer_guard', 'aws_iam_policy.deployer_iam', 'aws_iam_policy.deployer_state']), ('publisher', ['aws_iam_role_policy.publisher']))
    def combine_documents(addresses):
        versions = set()
        statements = []
        for address in addresses:
            policy = json.loads(policies[address])
            versions.add(policy['Version'])
            raw_statements = policy['Statement']
            statements.extend(raw_statements if isinstance(raw_statements, list) else [raw_statements])
        if len(versions) != 1: raise SystemExit(f'FAIL: oracle source policies disagree on Version: {addresses}')
        return json.dumps({'Version': next(iter(versions)), 'Statement': statements}, separators=(',', ':'))
    expected_by_kind = {}
    expected_roles = []
    projection_for_document = {}
    for kind, documents in role_documents:
        combined_policy = combine_documents(documents)
        source_size = sum((len(re.sub('\\s', '', policies[address])) for address in documents))
        if len(re.sub('\\s', '', combined_policy)) <= 10240: pass_specs = [('combined', documents, combined_policy, source_size)]
        else: pass_specs = [('per-document', [address], policies[address], len(re.sub('\\s', '', policies[address]))) for address in documents]
        expected_by_kind[kind] = []
        for pass_index, (projection_kind, addresses, policy, source_count) in enumerate(pass_specs, 1):
            projection_id = f'{kind}:combined' if projection_kind == 'combined' else f'{kind}:{addresses[0]}'
            role_name = f'orbit-iam-sim-fixture-run-{kind}'
            policy_name = f'orbit-iam-sim-{kind}'
            if len(pass_specs) > 1:
                role_name += f'-p{pass_index}'
                policy_name += f'-p{pass_index}'
            policy_sha256 = hashlib.sha256(policy.encode('utf-8')).hexdigest()
            spec = {'role_kind': kind, 'projection_kind': projection_kind, 'projection_id': projection_id, 'name': role_name, 'policy_name': policy_name, 'policy_document': policy, 'policy_sha256': policy_sha256, 'redacted_policy_sha256': policy_sha256, 'policy_character_count': len(re.sub('\\s', '', policy)), 'source_character_count': source_count, 'source_addresses': addresses}
            expected_by_kind[kind].append(spec)
            expected_roles.append(spec)
            for address in addresses: projection_for_document[address] = spec
    readiness_by_projection = {}
    for vector in vectors_in_order:
        expect = vector.get('expect', {})
        required = expect.get('matched_sid_required', [])
        if (
            vector.get('assertion_kind') == 'decision'
            and required
            and expect.get('decision') in {'allowed', 'explicitDeny'}
        ):
            projection = projection_for_document[vector['document']]
            readiness_by_projection.setdefault(projection['projection_id'], vector)
    for expected in expected_roles:
        readiness = readiness_by_projection.get(expected['projection_id'])
        if readiness is None:
            raise SystemExit(f"FAIL: fixture projection lacks readiness case: {expected['projection_id']}")
        expected['readiness_case'] = readiness
    roles = payload.get('projection', {}).get('roles', [])
    if len(roles) != len(expected_roles):
        expected_count = 'eight' if len(expected_roles) == 8 else str(len(expected_roles))
        raise SystemExit(f'FAIL: role projection requires {expected_count} passes, found {len(roles)}')
    by_kind = {}
    for role in roles: by_kind.setdefault(role.get('role_kind'), []).append(role)
    for kind, documents in role_documents:
        projections = by_kind.get(kind, [])
        actual_addresses = [entry.get('address') for projection in projections for entry in projection.get('source_documents', [])]
        if actual_addresses != documents: raise SystemExit(f'FAIL: role projection {kind} source order is {actual_addresses}')
        expected_projections = expected_by_kind[kind]
        if len(projections) != len(expected_projections): raise SystemExit(f'FAIL: role projection {kind} pass partition count is {len(projections)}, expected {len(expected_projections)}')
        for projection, expected in zip(projections, expected_projections):
            source_entries = projection.get('source_documents', [])
            source_addresses = [entry.get('address') for entry in source_entries]
            if source_addresses != expected['source_addresses']: raise SystemExit(f'FAIL: role projection {kind} source order is {source_addresses}')
            if projection.get('projection_kind') != expected['projection_kind']: raise SystemExit(f"FAIL: role projection {kind} partition kind is {projection.get('projection_kind')}, expected {expected['projection_kind']}")
            for entry, address in zip(source_entries, source_addresses):
                expected_hash = hashlib.sha256(policies[address].encode('utf-8')).hexdigest()
                if entry.get('sha256') != expected_hash: raise SystemExit(f'FAIL: role projection source hash differs for {address}')
            projected_policy = projection.get('policy_document')
            if projected_policy != expected['policy_document']: raise SystemExit(f"FAIL: role projection did not concatenate statements in source order: {projection.get('projection_id')}")
            if projection.get('policy_sha256') != expected['policy_sha256']: raise SystemExit(f"FAIL: role projection policy hash differs: {projection.get('projection_id')}")
            if (
                projection.get('redacted_policy_sha256')
                != expected['redacted_policy_sha256']
            ):
                raise SystemExit(
                    'FAIL: role projection redacted policy hash differs: '
                    f"{projection.get('projection_id')}"
                )
            for field in ('projection_id', 'name', 'policy_name', 'policy_character_count', 'source_character_count'):
                if projection.get(field) != expected[field]: raise SystemExit(f"FAIL: role projection {field} differs: {projection.get('projection_id')}")
            readiness = projection.get('readiness_case', {})
            if readiness.get('case_id') != expected['readiness_case']['case_id']:
                raise SystemExit(f"FAIL: role projection readiness case differs: {projection.get('projection_id')}")
            attempts = projection.get('propagation_attempts')
            delay = int(sys.argv[5]) if len(sys.argv) > 5 else 0
            if attempts != {'readback': delay + 1, 'probe': delay + 1}:
                raise SystemExit(f"FAIL: role projection propagation attempts differ: {projection.get('projection_id')}")
    records = payload.get('records', [])
    expected_case_ids = sorted(vector['case_id'] for vector in vectors_in_order)
    actual_case_ids = [record.get('case_id') for record in records]
    if actual_case_ids != expected_case_ids: raise SystemExit('FAIL: role projection report records are not sorted by case_id')
    for record in records:
        case_id = record['case_id']
        projection = record.get('projection', {})
        expected = projection_for_document[vectors[case_id]['document']]
        if projection.get('projection_id') != expected['projection_id']: raise SystemExit(f'FAIL: role projection record does not identify its deciding pass: {case_id}')
        if projection.get('policy_sha256') != expected['policy_sha256']: raise SystemExit(f'FAIL: role projection record policy hash differs: {case_id}')
        source_addresses = [entry.get('address') for entry in projection.get('source_documents', [])]
        if source_addresses != expected['source_addresses']: raise SystemExit(f'FAIL: role projection record source order differs: {case_id}')
    if payload.get('summary', {}).get('cases_selected') != len(vectors): raise SystemExit('FAIL: role projection summary selected count is wrong')
    call_paths = sorted(Path(sys.argv[4]).glob('*.json'), key=lambda path: int(path.stem))
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    role_names = [expected['name'] for expected in expected_roles]
    delay = int(sys.argv[5]) if len(sys.argv) > 5 else 0
    empty = ((), ())
    expected_calls = [('sts', 'get-caller-identity', None, False, *empty)]
    expected_calls.extend((('iam', 'create-role', name, False, *empty) for name in role_names))
    expected_calls.extend((('iam', 'list-role-tags', name, False, *empty) for name in role_names))
    for expected in expected_roles:
        name = expected['name']
        readiness = expected['readiness_case']
        actions = tuple(readiness['action_names'])
        resources = tuple(item.replace('${ACCOUNT_ID}', '000000000000').replace('${SUFFIX}', '79s5rw') for item in readiness['resource_arns'])
        expected_calls.append(('iam', 'put-role-policy', name, False, *empty))
        expected_calls.extend((('iam', 'get-role-policy', name, False, *empty) for _ in range(delay + 1)))
        expected_calls.extend((('iam', 'simulate-principal-policy', name, True, actions, resources) for _ in range(delay + 1)))
    for vector in vectors_in_order:
        role_name = projection_for_document[vector['document']]['name']
        resources = tuple(item.replace('${ACCOUNT_ID}', '000000000000').replace('${SUFFIX}', '79s5rw') for item in vector['resource_arns'])
        for action_group in _authorization_action_groups(vector['action_names']):
            expected_calls.append(('iam', 'simulate-principal-policy', role_name, True, tuple(action_group), resources))
        for action_group in _authorization_action_groups(vector['action_names']):
            expected_calls.append(('iam', 'simulate-principal-policy', role_name, False, tuple(action_group), resources))
    for name in reversed(role_names): expected_calls.extend((('iam', 'list-role-tags', name, False, *empty), ('iam', 'delete-role-policy', name, False, *empty), ('iam', 'list-role-tags', name, False, *empty), ('iam', 'delete-role', name, False, *empty)))
    expected_calls.extend((('iam', 'get-role', name, False, *empty) for name in role_names))
    actual_calls = []
    for call in calls:
        service, operation = call[:2]
        actions = ()
        resources = ()
        if operation == 'simulate-principal-policy':
            source_arn = call[call.index('--policy-source-arn') + 1]
            name = source_arn.rsplit('/', 1)[-1]
            excluded = '--policy-exclusion-list' in call
            actions = tuple(_option(call, '--action-names'))
            resources = tuple(_option(call, '--resource-arns'))
        elif '--role-name' in call:
            name = call[call.index('--role-name') + 1]
            excluded = False
        else:
            name = None
            excluded = False
        actual_calls.append((service, operation, name, excluded, actions, resources))
    if actual_calls != expected_calls:
        mismatch = next((index for index, (actual, expected) in enumerate(zip(actual_calls, expected_calls)) if actual != expected), min(len(actual_calls), len(expected_calls)))
        raise SystemExit(f'FAIL: role projection call ordering differs from plan and vectors at index {mismatch}')
def _command_mutate_role_projection_report():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    roles = payload['projection']['roles']
    index = next((index for index, role in enumerate(roles) if role.get('role_kind') == 'deployer'))
    roles.pop(index)
    Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
def _command_validate_role_divergence_report():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    summary = payload.get('summary', {})
    if summary.get('agreements') != 2 or summary.get('divergences') != 1: raise SystemExit('FAIL: role divergence summary must contain two agreements and one divergence')
    divergences = [record for record in payload.get('records', []) if record.get('comparison') == 'divergence']
    if len(divergences) != 1: raise SystemExit('FAIL: role divergence report must preserve one divergence record')
    record = divergences[0]
    evidence = record.get('divergence', {})
    if record.get('pass') is not True: raise SystemExit('FAIL: role divergence must not mark the case or run failed')
    if evidence.get('observed_in') != ['scp-excluded', 'default']: raise SystemExit('FAIL: role divergence must identify both principal runs')
    if evidence.get('custom_lane') != {'decision_observed': 'implicitDeny', 'matched_sids': ['CustomMatchedSid']}: raise SystemExit('FAIL: role divergence lost the custom-lane decision or matched Sids')
    for run in ('scp_excluded', 'default'):
        if evidence.get(run) != {'decision_observed': 'allowed', 'matched_sids': ['ReadStateObjects']}: raise SystemExit(f'FAIL: role divergence lost the {run} decision or matched Sids')
    projection = record.get('projection', {})
    if not projection.get('projection_id') or not projection.get('source_documents'): raise SystemExit('FAIL: role divergence does not identify its deciding projection')
def _command_mutate_role_source_logic():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    mutation = sys.argv[3]
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    if source.count(root_line) != 1: raise SystemExit('FAIL: role source mutation root anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[4])}', 1)
    builder_call = '    projection_specs = core.build_role_projections(documents, selected_roles)'
    insertions = {
        'partition': '    projection_specs[0]["source_documents"].reverse()',
        'concatenation': '''    mutated_policy = json.loads(projection_specs[0]["policy_document"])
    mutated_policy["Statement"].reverse()
    projection_specs[0]["policy_document"] = json.dumps(mutated_policy, separators=(",", ":"))
    projection_specs[0]["policy_sha256"] = core.document_sha256(projection_specs[0]["policy_document"])''',
        'hash': '    projection_specs[0]["policy_sha256"] = "0" * 64',
    }
    if mutation not in insertions: raise SystemExit(f'FAIL: unknown role source mutation: {mutation}')
    if source.count(builder_call) != 1: raise SystemExit(f'FAIL: role source {mutation} mutation anchor changed')
    replacement = f'{builder_call}\n{insertions[mutation]}'
    destination.write_text(source.replace(builder_call, replacement, 1), encoding='utf-8')
    destination.chmod(493)
def _command_mutate_role_divergence_report():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    record = next((item for item in payload['records'] if item.get('comparison') == 'divergence'))
    record['comparison'] = 'agreement'
    record.pop('divergence')
    payload['summary']['agreements'] += 1
    payload['summary']['divergences'] -= 1
    Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
def _command_validate_role_two_runs():
    call_paths = sorted(Path(sys.argv[1]).glob('*.json'), key=lambda path: int(path.stem))
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    payload = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
    records = payload.get('records', [])
    simulation_count = 2 * len(records)
    simulations = [
        args for args in calls
        if args[:2] == ['iam', 'simulate-principal-policy']
    ][-simulation_count:]
    if len(simulations) != 2 * len(records): raise SystemExit('FAIL: two-run contract requires exactly two simulations per selected case')
    exclusion = '{"PolicyType":"scp"}'
    for index in range(0, len(simulations), 2):
        excluded = simulations[index]
        default = simulations[index + 1]
        if excluded.count('--policy-exclusion-list') != 1: raise SystemExit('FAIL: two-run contract requires one exact scp-excluded call and one default call per case')
        option_index = excluded.index('--policy-exclusion-list')
        if excluded[option_index + 1] != exclusion or '--policy-exclusion-list' in default: raise SystemExit('FAIL: two-run contract requires one exact scp-excluded call and one default call per case')
        if excluded[:option_index] + excluded[option_index + 2:] != default: raise SystemExit('FAIL: two-run contract changed inputs other than the SCP exclusion')
    for record in records:
        if record.get('comparison') != 'agreement': raise SystemExit('FAIL: two-run contract did not compare the scp-excluded run to custom')
        if record.get('scp_excluded', {}).get('decision_observed') != 'allowed' or record.get('default', {}).get('decision_observed') != 'explicitDeny': raise SystemExit('FAIL: two-run contract lost the separate effective-policy decision')
        divergences = record.get('organizations_divergences', [])
        if len(divergences) != 1: raise SystemExit('FAIL: two-run contract must report each Organizations divergence')
        divergence = divergences[0]
        if not divergence.get('action_name') or not divergence.get('resource_arn'): raise SystemExit('FAIL: Organizations divergence lacks action and resource attribution')
        sources = divergence.get('default', {}).get('matched_statement_sources', [])
        if not any((source.get('source_policy_type') == 'Organizations Policy' for source in sources)): raise SystemExit('FAIL: Organizations divergence lacks default-run source attribution')
    if payload.get('summary', {}).get('organizations_divergences') != len(records): raise SystemExit('FAIL: two-run summary Organizations divergence count is wrong')
def _command_mutate_role_two_run_calls():
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    shutil.copytree(source, destination)
    paths = sorted(destination.glob('*.json'), key=lambda item: int(item.stem))
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in paths]
    last_put = max(
        index for index, args in enumerate(calls)
        if args[:2] == ['iam', 'put-role-policy']
    )
    skipped_readiness = False
    for path, args in zip(paths[last_put + 1:], calls[last_put + 1:]):
        if args[:2] != ['iam', 'simulate-principal-policy'] or '--policy-exclusion-list' not in args:
            continue
        if not skipped_readiness:
            skipped_readiness = True
            continue
        index = args.index('--policy-exclusion-list')
        del args[index:index + 2]
        path.write_text(json.dumps(args) + '\n', encoding='utf-8')
        break
    else: raise SystemExit('FAIL: two-run mutation found no scp-excluded case simulation')
def _command_validate_full_scale_role_dry_run():
    inventory_path = Path(sys.argv[1])
    plan_path = Path(sys.argv[2])
    vectors_path = Path(sys.argv[3])
    role_for_document = {'aws_iam_role_policy.plan_reader_deny': 'plan-reader', 'aws_iam_role_policy.plan_reader_state': 'plan-reader', 'aws_iam_policy.deployer_state': 'deployer', 'aws_iam_policy.deployer_ec2': 'deployer', 'aws_iam_policy.deployer_elb_ecs': 'deployer', 'aws_iam_policy.deployer_data': 'deployer', 'aws_iam_policy.deployer_iam': 'deployer', 'aws_iam_policy.deployer_guard': 'deployer', 'aws_iam_role_policy.publisher': 'publisher'}
    plan = json.loads(plan_path.read_text(encoding='utf-8'))
    resources = plan['planned_values']['root_module']['resources']
    documents = {resource['address']: resource['values']['policy'] for resource in resources if resource.get('address') in role_for_document}
    vectors = [{'schema_version': envelope['schema_version'], 'document': envelope['document'], 'sid': envelope['sid'], **case} for path in sorted(vectors_path.rglob('*.json')) for envelope in [json.loads(path.read_text(encoding='utf-8'))] for case in envelope['cases']]
    eligible = [vector for vector in vectors if vector.get('simulation_mode') == 'custom' and vector.get('document') in role_for_document]
    selected = [vector for role in ('plan-reader', 'deployer', 'publisher') for vector in eligible if role_for_document[vector['document']] == role]
    selected_roles = {role_for_document[vector['document']] for vector in selected}
    role_count = 0
    for role in selected_roles:
        addresses = sorted((address for address, mapped_role in role_for_document.items() if mapped_role == role))
        policies = [json.loads(documents[address]) for address in addresses]
        versions = {policy['Version'] for policy in policies}
        statements = []
        for policy in policies:
            policy_statements = policy['Statement']
            statements.extend(policy_statements if isinstance(policy_statements, list) else [policy_statements])
        combined = json.dumps({'Version': next(iter(versions)), 'Statement': statements}, separators=(',', ':'))
        role_count += 1 if len(re.sub(r'\s', '', combined)) <= 10240 else len(addresses)
    case_count = len(selected)
    action_group_count = sum(len(_authorization_action_groups(vector['action_names'])) for vector in selected)
    expected_calls = 1 + 8 * role_count + 2 * action_group_count
    lines = [line for line in inventory_path.read_text(encoding='utf-8').splitlines() if line.startswith('DRY-RUN:')]
    if len(lines) != expected_calls: raise SystemExit(f'FAIL: full-fixture dry-run call count is {len(lines)}, expected 1 + 8*{role_count} + 2*{action_group_count} = {expected_calls}')
    operations = Counter()
    for operation in ('create-role', 'list-role-tags', 'put-role-policy', 'simulate-principal-policy', 'delete-role-policy', 'delete-role', 'get-role'): operations[operation] = sum((re.search(f' iam {operation}(?: |$)', line) is not None for line in lines))
    expected_operations = {'create-role': role_count, 'list-role-tags': 3 * role_count, 'put-role-policy': role_count, 'simulate-principal-policy': 2 * action_group_count, 'delete-role-policy': role_count, 'delete-role': role_count, 'get-role': role_count}
    if dict(operations) != expected_operations: raise SystemExit(f'FAIL: full-fixture dry-run operation counts differ: {dict(operations)}')
    if sum((' sts get-caller-identity ' in line for line in lines)) != 1: raise SystemExit('FAIL: full-fixture dry-run requires one caller identity call')
    simulations = [line for line in lines if ' iam simulate-principal-policy ' in line]
    exclusion = '{"PolicyType":"scp"}'
    cursor = 0
    for vector in selected:
        action_groups = _authorization_action_groups(vector['action_names'])
        grouped_calls = simulations[cursor:cursor + 2 * len(action_groups)]
        cursor += len(grouped_calls)
        expected_grouped_calls = ([(group, True) for group in action_groups] + [(group, False) for group in action_groups])
        for line, (expected_actions, excluded) in zip(grouped_calls, expected_grouped_calls):
            call = shlex.split(line.removeprefix('DRY-RUN:'))
            if _option(call, '--action-names') != expected_actions:
                raise SystemExit('FAIL: full-fixture dry-run action groups differ from selected vectors')
            exclusions = _option(call, '--policy-exclusion-list')
            if exclusions != ([exclusion] if excluded else []):
                raise SystemExit('FAIL: full-fixture dry-run must emit every scp-excluded group before every default group for each case')
    if cursor != len(simulations): raise SystemExit('FAIL: full-fixture dry-run contains unexpected principal simulations')
    print(f'R={role_count} C={case_count} G={action_group_count} calls={expected_calls}')
def _command_prepare_fd_vectors():
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    limit = int(sys.argv[3])
    supported_documents = {'aws_iam_role_policy.plan_reader_deny', 'aws_iam_role_policy.plan_reader_state', 'aws_iam_policy.deployer_state', 'aws_iam_policy.deployer_ec2', 'aws_iam_policy.deployer_elb_ecs', 'aws_iam_policy.deployer_data', 'aws_iam_policy.deployer_iam', 'aws_iam_policy.deployer_guard', 'aws_iam_role_policy.publisher'}
    selected = []
    for source_path in sorted(source.rglob('*.json')):
        envelope = json.loads(source_path.read_text(encoding='utf-8'))
        cases = [case for case in envelope['cases'] if case.get('simulation_mode') == 'custom' and envelope['document'] in supported_documents]
        if cases: selected.append((envelope, cases))
        if sum((len(cases) for _, cases in selected)) >= limit: break
    remaining = limit
    if destination.exists(): shutil.rmtree(destination)
    destination.mkdir()
    written = 0
    for envelope, cases in selected:
        cases = cases[:remaining]
        if not cases: break
        reduced = {'schema_version': envelope['schema_version'], 'document': envelope['document'], 'sid': envelope['sid'], 'cases': cases}
        (destination / f'fd-{written:03d}.json').write_text(json.dumps(reduced, indent=2) + '\n', encoding='utf-8')
        written += 1
        remaining -= len(cases)
    if remaining: raise SystemExit(f'FAIL: reduced FD fixture contains {limit - remaining} cases, expected {limit}')
def _instrument_role_fd_reads(source_path, repo_root):
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    function_anchor = 'read_case_record() {'
    dry_run_loop = '  while read_case_record; do'
    live_loop = '\nwhile read_case_record; do'
    if source.count(root_line) != 1: raise SystemExit('FAIL: role FD probe root anchor changed')
    if source.count(function_anchor) != 1: raise SystemExit('FAIL: role FD probe function anchor changed')
    if source.count(dry_run_loop) != 1: raise SystemExit('FAIL: role FD probe dry-run loop anchor changed')
    if source.count(live_loop) != 1: raise SystemExit('FAIL: role FD probe live loop anchor changed')
    probe_function = r'''record_open_fd_count() {
  local fd_count
  if [ -z "${IAM_SIM_TEST_FD_SAMPLES:-}" ]; then
    return 0
  fi
  fd_count="$(ls -1 /dev/fd | wc -l | tr -d ' ')"
  printf '%s\t%s\n' "$1" "$fd_count" >>"$IAM_SIM_TEST_FD_SAMPLES"
}

'''
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(repo_root)}', 1)
    source = source.replace(function_anchor, probe_function + function_anchor, 1)
    source = source.replace(dry_run_loop, dry_run_loop + '\n    record_open_fd_count "$case_index"', 1)
    return source.replace(live_loop, live_loop + '\n  record_open_fd_count "$case_index"', 1)


def _command_mutate_role_deterministic_fd_leak():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = _instrument_role_fd_reads(source_path, sys.argv[3])
    dry_probe = '\n    record_open_fd_count "$case_index"'
    live_probe = '\n  record_open_fd_count "$case_index"'
    if source.count(dry_probe) != 1 or source.count(live_probe) != 1:
        raise SystemExit('FAIL: deterministic role FD mutation anchors changed')
    dry_leak = '\n    eval "exec $((10 + case_index))<\"$case_stream\""' + dry_probe
    live_leak = '\n  eval "exec $((10 + case_index))<\"$case_stream\""' + live_probe
    source = source.replace(dry_probe, dry_leak, 1)
    source = source.replace(live_probe, live_leak, 1)
    destination.write_text(source, encoding='utf-8')


def _command_instrument_role_fd_reads():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    destination.write_text(_instrument_role_fd_reads(source_path, sys.argv[3]), encoding='utf-8')


def _load_fd_samples(path, expected_count):
    try:
        lines = path.read_text(encoding='utf-8').splitlines()
    except OSError as exc:
        raise SystemExit(f'FAIL: role-lane FD samples cannot be read: {exc}') from exc
    if len(lines) != expected_count:
        raise SystemExit(f'FAIL: role-lane FD probe recorded {len(lines)} samples, expected {expected_count}')
    samples = []
    for expected_index, line in enumerate(lines):
        fields = line.split('\t')
        if len(fields) != 2:
            raise SystemExit(f'FAIL: role-lane FD sample {expected_index} is malformed')
        try:
            case_index, fd_count = (int(field) for field in fields)
        except ValueError as exc:
            raise SystemExit(f'FAIL: role-lane FD sample {expected_index} is not numeric') from exc
        if case_index != expected_index:
            raise SystemExit(f'FAIL: role-lane FD sample index is {case_index}, expected {expected_index}')
        if fd_count < 0:
            raise SystemExit(f'FAIL: role-lane FD sample {expected_index} has a negative count')
        samples.append(fd_count)
    return samples


def _command_validate_fd_leak_probe():
    samples = _load_fd_samples(Path(sys.argv[1]), int(sys.argv[2]))
    growth = [after - before for before, after in zip(samples, samples[1:])]
    for index, step in enumerate(growth, 1):
        if step < 1:
            raise SystemExit(
                f'FAIL: role-lane deterministic descriptor growth was {step} at '
                f'case transition {index - 1}->{index}, expected at least 1'
            )
    raise SystemExit(
        'FAIL: role-lane deterministic descriptor count grew by at least 1 per case '
        f'({len(samples)} samples; {samples[0]}->{samples[-1]}; minimum step={min(growth)})'
    )


def _command_validate_fd_stability_probe():
    samples = _load_fd_samples(Path(sys.argv[1]), int(sys.argv[2]))
    minimum = min(samples)
    maximum = max(samples)
    spread = maximum - minimum
    if spread > 2:
        raise SystemExit(
            f'FAIL: role-lane descriptor count spread is {spread}, expected at most 2 '
            f'(min={minimum}; max={maximum})'
        )
    print(
        f'PASS: role-lane descriptor count stayed flat '
        f'({len(samples)} samples; min={minimum}; max={maximum}; spread={spread})'
    )
def _command_run_full_scale_role_dry_run():
    role_lane, plan, vectors, output_path, timeout_seconds, phase2_dir, wrapper = sys.argv[1:]
    environment = os.environ.copy()
    environment.pop('AWS_PROFILE', None)
    environment.update({'PATH': f"{phase2_dir}/bin:{environment['PATH']}", 'AWS_CLI_BIN': 'aws', 'AWS_CLI_SH': wrapper, 'FAKE_AWS_CALL_DIR': f'{phase2_dir}/calls', 'FAKE_ROLE_STATE_DIR': f'{phase2_dir}/roles', 'FAKE_AWS_SCENARIO': 'success', 'FAKE_ACCOUNT_ID': '000000000000', 'IAM_SIM_RUN_ID': 'full-fixture', 'TARGET': 'aws'})
    command = [role_lane, '--plan', plan, '--vectors', vectors, '--report', f'{phase2_dir}/full-fixture-dry-report.json', '--expect-account', '000000000000', '--dry-run']
    process = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=int(timeout_seconds))
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            output, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
        Path(output_path).write_text(output, encoding='utf-8')
        raise SystemExit(f'FAIL: full-fixture role-lane dry-run exceeded {timeout_seconds} seconds')
    Path(output_path).write_text(output, encoding='utf-8')
    if process.returncode != 0: raise SystemExit(f'FAIL: full-fixture role-lane dry-run exited {process.returncode}')
def _command_mutate_core_counter():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    anchor = 'def main() -> int:\n'
    instrumentation = 'def main() -> int:\n    import os\n\n    call_log = os.environ.get("IAM_SIM_TEST_CORE_CALL_LOG")\n    if call_log and len(sys.argv) > 1:\n        with Path(call_log).open("a", encoding="utf-8") as handle:\n            handle.write(sys.argv[1] + "\\n")\n'
    if source.count(anchor) != 1: raise SystemExit('FAIL: shared-core counter mutation anchor changed')
    destination.write_text(source.replace(anchor, instrumentation, 1), encoding='utf-8')
def _command_mutate_report_writer():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    start_marker = 'def write_report(path: Path, payload: dict[str, Any]) -> None:\n'
    end_marker = '\n\ndef document_hashes('
    if source.count(start_marker) != 1 or source.count(end_marker) != 1: raise SystemExit('FAIL: compact report writer mutation anchors changed')
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    pretty_writer = """def write_report(path: Path, payload: dict[str, Any]) -> None:
    payload = redact_report(payload)
    payload["redaction_applied"] = True
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\\n", encoding="utf-8"
    )
"""
    destination.write_text(source[:start] + pretty_writer + source[end:], encoding='utf-8')


def _command_mutate_report_temp_directory():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    strict = '            dir=path.parent,\n'
    if source.count(strict) != 1:
        raise SystemExit('FAIL: report temp-directory mutation anchor changed')
    destination.write_text(source.replace(strict, '            dir=None,\n', 1), encoding='utf-8')


def _command_mutate_report_redaction():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    strict = '    payload = redact_report(payload)\n'
    if source.count(strict) != 1: raise SystemExit('FAIL: shared report redaction mutation anchor changed')
    destination.write_text(source.replace(strict, '    payload = dict(payload)\n', 1), encoding='utf-8')


def _command_mutate_report_principal_redaction():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    strict = '        value = REPORT_PRINCIPAL_ARN.sub(REPORT_REDACTED_PRINCIPAL, value)\n'
    if source.count(strict) != 1:
        raise SystemExit('FAIL: shared report principal-redaction mutation anchor changed')
    destination.write_text(source.replace(strict, '        value = value\n', 1), encoding='utf-8')


def _command_validate_report_principal_redaction():
    core_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location('iam_simulate_core_principal', core_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f'FAIL: cannot load IAM simulator core: {core_path}')
    core = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = core
    spec.loader.exec_module(core)
    principals = [
        'arn:aws:iam::123456789012:user/Alice',
        'arn:aws:iam::123456789012:role/team/DeployRole',
        'arn:aws:iam::123456789012:assumed-role/DeployRole/session',
        'arn:aws:iam::123456789012:group/team/Admins',
        'arn:aws:iam::123456789012:federated-user/Alice',
        'arn:aws:sts::123456789012:assumed-role/DeployRole/session',
    ]
    payload = {
        'recorded_at': '2026-09-10T00:00:00Z',
        'records': [{
            'case_id': 'case:principal-redaction',
            'runner_failure': ' | '.join(principals),
        }],
        'summary': {'total': 1},
    }
    core.write_report(output_path, payload)
    actual = json.loads(output_path.read_text(encoding='utf-8'))
    expected = ' | '.join(
        ['arn:aws:iam::000000000000:<redacted-principal>'] * len(principals)
    )
    if actual['records'][0].get('runner_failure') != expected:
        raise SystemExit('FAIL: shared report writer retained principal identity path')
    print('PASS: shared report writer fully redacts IAM and STS principal paths')


def _command_mutate_artifact_hygiene_principal_arn():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    strict = '        if identity_path != REDACTED_PRINCIPAL:  # principal-arn-guard\n'
    if source.count(strict) != 1:
        raise SystemExit('FAIL: artifact hygiene principal-ARN mutation anchor changed')
    destination.write_text(
        source.replace(strict, '        if False:  # principal-arn-guard\n', 1),
        encoding='utf-8',
    )


def _command_mutate_evidence_suffix_check():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    strict = '    pattern = pattern.replace(re.escape("${SUFFIX}"), re.escape(report_suffix))\n'
    if source.count(strict) != 1:
        raise SystemExit('FAIL: Evidence suffix-check mutation anchor changed')
    destination.write_text(
        source.replace(
            strict,
            '    pattern = pattern.replace(re.escape("${SUFFIX}"), r"[a-z0-9]+")\n',
            1,
        ),
        encoding='utf-8',
    )


def _command_validate_report_atomic_replace():
    core_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    external_scratch = Path(sys.argv[3])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    external_scratch.mkdir(parents=True, exist_ok=True)
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location('iam_simulate_core_atomic', core_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f'FAIL: cannot load IAM simulator core: {core_path}')
    core = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = core
    spec.loader.exec_module(core)
    if not hasattr(core, 'os') or not hasattr(core, 'tempfile'):
        raise SystemExit('FAIL: shared report writer did not atomically replace its destination')
    replacements = []
    real_replace = core.os.replace
    core.tempfile.tempdir = str(external_scratch)

    def guarded_replace(source, destination):
        source_path = Path(source)
        destination_path = Path(destination)
        replacements.append((source_path, destination_path))
        if source_path.parent != destination_path.parent:
            raise OSError(18, 'Invalid cross-device link')
        return real_replace(source_path, destination_path)

    core.os.replace = guarded_replace
    try:
        core.write_report(
            output_path,
            {
                'recorded_at': '2026-09-10T00:00:00Z',
                'records': [],
                'summary': {'total': 0},
            },
        )
    except OSError as exc:
        if exc.errno == 18:
            raise SystemExit('FAIL: shared report writer attempted cross-directory replacement') from exc
        raise
    if len(replacements) != 1:
        raise SystemExit('FAIL: shared report writer did not atomically replace its destination')
    if replacements[0][0].parent != output_path.parent:
        raise SystemExit('FAIL: shared report writer attempted cross-directory replacement')
    if json.loads(output_path.read_text(encoding='utf-8')).get('redaction_applied') is not True:
        raise SystemExit('FAIL: shared report writer atomic replacement changed report content')
    print('PASS: shared report writer atomically replaced from the destination directory')


def _command_validate_report_writer():
    core_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location('iam_simulate_core', core_path)
    if spec is None or spec.loader is None: raise SystemExit(f'FAIL: cannot load IAM simulator core: {core_path}')
    core = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = core
    spec.loader.exec_module(core)
    payload = {
        'account': '000000000000',
        'recorded_at': '2026-09-10T00:00:00Z',
        'exclusions': [
            {'binding': 'fixture.binding', 'reason': 'no case id'},
            {'case_id': 'case:a', 'reason': 'first'},
            {'case_id': 'case:z', 'reason': 'last'},
        ],
        'records': [
            {
                'case_id': 'case:a',
                'errors': [
                    'live 123456789012 arn:aws:iam::210987654321:role/example '
                    'AROAEXAMPLE1234567'
                ],
                'mode': 'custom',
                'nested': {'z': 4, 'a': 3},
                'pass': True,
                'response': {'RequestId': 'request-token'},
                'trace_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
            },
            {'case_id': 'case:z', 'nested': {'z': 2, 'a': 1}, 'pass': True},
        ],
        'summary': {'total': 2, 'passed': 2, 'failed': 0},
    }
    expected_payload = deepcopy(payload)
    expected_payload['records'][0]['errors'] = [
        'live 000000000000 arn:aws:iam::000000000000:<redacted-principal> <redacted>'
    ]
    expected_payload['records'][0]['response'] = {'<redacted>': '<redacted>'}
    expected_payload['records'][0]['trace_id'] = '<redacted>'
    expected_payload['redaction_applied'] = True
    core.write_report(output_path, payload)
    rendered = output_path.read_text(encoding='utf-8')
    actual_payload = json.loads(rendered)
    if (
        '123456789012' in rendered
        or 'AROAEXAMPLE1234567' in rendered
        or actual_payload.get('redaction_applied') is not True
    ):
        raise SystemExit('FAIL: shared report writer retained live identifiers')
    lines = rendered.splitlines()
    keys = sorted(expected_payload)
    for key in ('records', 'exclusions'):
        diagnostic = f'FAIL: compact report {key} must contain exactly one record per line'
        opener = f'  {json.dumps(key)}:['
        if opener not in lines: raise SystemExit(diagnostic)
        start = lines.index(opener) + 1
        try: end = lines.index('  ]' + (',' if keys.index(key) < len(keys) - 1 else ''), start)
        except ValueError: raise SystemExit(diagnostic) from None
        values = sorted(expected_payload[key], key=lambda item: item.get('case_id', ''))
        expected = [
            '    ' + json.dumps(item, sort_keys=True, separators=(',', ':')) +
            (',' if index < len(values) - 1 else '')
            for index, item in enumerate(values)
        ]
        if lines[start:end] != expected: raise SystemExit(diagnostic)
    for key in set(keys) - {'records', 'exclusions'}:
        expected = (
            f'  {json.dumps(key)}:' +
            json.dumps(expected_payload[key], sort_keys=True, separators=(',', ':')) +
            (',' if keys.index(key) < len(keys) - 1 else '')
        )
        if lines.count(expected) != 1: raise SystemExit(f'FAIL: compact report top-level key is not on one line: {key}')
    if actual_payload != expected_payload: raise SystemExit('FAIL: compact report changes JSON content')
    print('PASS: compact report writer preserves content and renders sorted one-record lines')


def _command_mutate_renderer_role_outcome():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    mutation = sys.argv[3]
    payload = json.loads(source_path.read_text(encoding='utf-8'))
    custom_path = Path(sys.argv[4])
    custom = json.loads(custom_path.read_text(encoding='utf-8'))
    custom_by_id = {record['case_id']: record for record in custom['records']}
    record = next(
        record for record in payload['records']
        if isinstance(record.get('scp_excluded', {}).get('details'), list)
        and record['scp_excluded']['details']
        and record['case_id'] in custom_by_id
        and custom_by_id[record['case_id']].get('details')
    )
    details = record['scp_excluded']['details']
    if mutation == 'decision':
        details[0]['decision_observed'] = (
            'implicitDeny'
            if details[0]['decision_observed'] != 'implicitDeny'
            else 'allowed'
        )
    elif mutation == 'deleted-pair':
        details.pop()
    elif mutation == 'truncated-pair':
        if len(details) < 2 or len(record['custom_lane']['details']) < 2:
            raise SystemExit(
                'FAIL: renderer truncated-pair mutation requires two detail pairs'
            )
        details.pop()
        record['custom_lane']['details'].pop()
    elif mutation == 'duplicate-pair':
        details.append(deepcopy(details[0]))
    elif mutation == 'malformed-details':
        details[0] = 'not-an-object'
    elif mutation == 'empty-pairs':
        details.clear()
        record['custom_lane']['details'] = []
    elif mutation == 'substituted-resource':
        details[0]['resource_arn'] = 'arn:aws:s3:::orbit-infra-fixture-substituted'
    else:
        raise SystemExit(f'FAIL: unknown renderer role-outcome mutation: {mutation}')
    record['pass'] = True
    destination.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(record['case_id'])


def _command_mutate_renderer_role_expectation():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    mutation = sys.argv[3]
    payload = json.loads(source_path.read_text(encoding='utf-8'))
    record = payload['records'][0]
    record['case_id'] = 'case:fixture.policy:UnknownRead:ALL:none:matching'
    if mutation == 'missing-source':
        record.pop('expect', None)
    elif mutation == 'empty-expectation':
        record['expect'] = {}
    else:
        raise SystemExit(
            f'FAIL: unknown renderer role-expectation mutation: {mutation}'
        )
    destination.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8'
    )


def _command_validate_renderer_role_outcome():
    report_path = Path(sys.argv[1])
    case_id = sys.argv[2]
    rendered = report_path.read_text(encoding='utf-8')
    rows = [line for line in rendered.splitlines() if line.startswith(f'| {case_id} | principal |')]
    if len(rows) != 1 or not rows[0].endswith('| no |'):
        raise SystemExit(f'FAIL: renderer role outcome mutant remained passing: {case_id}')
    findings = rendered.split('## Findings', 1)[1].split('## Divergences', 1)[0]
    if case_id not in findings or '(role)' not in findings:
        raise SystemExit(f'FAIL: renderer role outcome mutant lacks a role finding: {case_id}')


def _command_mutate_role_empty_resources():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    repo_root = sys.argv[3]
    source = source_path.read_text(encoding='utf-8')
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    strict = '''    call_args=(
      iam simulate-principal-policy
      --policy-source-arn "arn:aws:iam::$expect_account:role/$CASE_ROLE_NAME"
      --action-names "${action_group[@]}"
    )
    if [ "${#CASE_RESOURCES[@]}" -gt 0 ]; then
      call_args+=(--resource-arns "${CASE_RESOURCES[@]}")
    fi
    call_args+=("${CASE_CONTEXT_ARGS[@]}")
'''
    mutant = '''    call_args=(
      iam simulate-principal-policy
      --policy-source-arn "arn:aws:iam::$expect_account:role/$CASE_ROLE_NAME"
      --action-names "${action_group[@]}"
      --resource-arns ${CASE_RESOURCES[@]+"${CASE_RESOURCES[@]}"}
      "${CASE_CONTEXT_ARGS[@]}"
    )
'''
    if source.count(root_line) != 1 or source.count(strict) != 1:
        raise SystemExit('FAIL: role empty-resource mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(repo_root)}', 1)
    destination.write_text(source.replace(strict, mutant, 1), encoding='utf-8')
    destination.chmod(0o755)


def _command_mutate_artifact_hygiene_field_scope():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    strict = '    sanitized = sanitize_scoped_hex(content, json_payload, line_no)\n'
    mutant = '    sanitized = HEX40.sub("", HEX64.sub("", content))\n'
    if source.count(strict) != 1:
        raise SystemExit('FAIL: artifact hygiene field-scope mutation anchor changed')
    destination.write_text(source.replace(strict, mutant, 1), encoding='utf-8')
    destination.chmod(0o755)


def _command_build_modern_evidence():
    custom_source, role_source, custom_out, role_out = map(Path, sys.argv[1:5])
    custom = json.loads(custom_source.read_text(encoding='utf-8'))
    custom['recorded_at'] = '2026-09-10T00:00:00Z'
    custom_out.write_text(json.dumps(custom, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    role = json.loads(role_source.read_text(encoding='utf-8'))
    role['recorded_at'] = '2026-09-10T00:00:01Z'
    role['custom_report_sha256'] = hashlib.sha256(custom_out.read_bytes()).hexdigest()
    role_out.write_text(json.dumps(role, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def _replace_provenance_digest(provenance_path, name, digest):
    source = provenance_path.read_text(encoding='utf-8')
    pattern = re.compile(rf'(?m)^(\| {re.escape(name)} \| )`?[0-9a-f]{{64}}`?( \|)$')
    updated, count = pattern.subn(rf'\g<1>{digest}\g<2>', source)
    if count != 1:
        raise SystemExit(f'FAIL: provenance digest mutation lacks row: {name}')
    provenance_path.write_text(updated, encoding='utf-8')


def _command_mutate_provenance_digest():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    mutation = sys.argv[3]
    source = source_path.read_text(encoding='utf-8')
    row = re.search(r'(?m)^\| custom report sha256 \| ([0-9a-f]{64}) \|$', source)
    if row is None:
        raise SystemExit('FAIL: provenance digest mutation lacks custom report row')
    if mutation == 'doctored':
        digest = row.group(1)
        replacement = ('0' if digest[0] != '0' else '1') + digest[1:]
        source = source[:row.start(1)] + replacement + source[row.end(1):]
    elif mutation == 'missing':
        source = source[:row.start()] + source[row.end() + 1:]
    else:
        raise SystemExit(f'FAIL: unknown provenance digest mutation: {mutation}')
    destination.write_text(source, encoding='utf-8')


def _command_mutate_evidence_hash_chain():
    custom_path = Path(sys.argv[1])
    role_source = Path(sys.argv[2])
    role_out = Path(sys.argv[3])
    provenance_path = Path(sys.argv[4])
    mutation = sys.argv[5]
    role = json.loads(role_source.read_text(encoding='utf-8'))
    case_id = 'case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource'
    record = next(record for record in role['records'] if record['case_id'] == case_id)
    projection_id = record['projection']['projection_id']
    projection = next(
        item for item in role['projection']['roles']
        if item['projection_id'] == projection_id
    )
    if projection_id != 'plan-reader:combined' or len(projection['source_documents']) != 2:
        raise SystemExit('FAIL: Evidence hash-chain mutation requires plan-reader:combined with two sources')
    if mutation == 'custom-to-role':
        record['document_hashes_submitted']['custom_lane'][0]['sha256'] = '0' * 64
    elif mutation == 'source-document':
        projection['source_documents'][0]['sha256'] = '0' * 64
    elif mutation == 'projection-policy':
        projection['policy_document'] += ' '
    elif mutation == 'put-role-policy':
        record['document_hashes_submitted']['put_role_policy'][0]['sha256'] = '0' * 64
    else:
        raise SystemExit(f'FAIL: unknown Evidence hash-chain mutation: {mutation}')
    role_out.write_text(json.dumps(role, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    _replace_provenance_digest(
        provenance_path, 'role report sha256', hashlib.sha256(role_out.read_bytes()).hexdigest()
    )
    print(case_id)


def _command_mutate_role_projection_source_binding():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    payload = json.loads(source_path.read_text(encoding='utf-8'))
    projection = next(
        item for item in payload['projection']['roles']
        if item.get('projection_id') == 'plan-reader:combined'
    )
    policy = json.loads(projection['policy_document'])
    statements = policy['Statement']
    if isinstance(statements, dict):
        statements = [statements]
    statements[0]['Effect'] = 'Allow' if statements[0].get('Effect') != 'Allow' else 'Deny'
    policy['Statement'] = statements
    policy_document = json.dumps(policy, separators=(',', ':'))
    policy_sha256 = hashlib.sha256(policy_document.encode('utf-8')).hexdigest()
    projection['policy_document'] = policy_document
    projection['policy_sha256'] = policy_sha256
    for record in payload['records']:
        if record.get('projection', {}).get('projection_id') != projection['projection_id']:
            continue
        record['projection']['policy_sha256'] = policy_sha256
        put_hashes = record.get('document_hashes_submitted', {}).get('put_role_policy', [])
        for entry in put_hashes:
            entry['sha256'] = policy_sha256
    destination.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8'
    )
    print(projection['projection_id'])


def _command_build_role_projection_account_redaction():
    plan_source, role_source, plan_out, role_out = map(Path, sys.argv[1:5])
    custom_source = Path(sys.argv[5]) if len(sys.argv) > 5 else None
    custom_out = Path(sys.argv[6]) if len(sys.argv) > 6 else None
    if (custom_source is None) != (custom_out is None):
        raise SystemExit('FAIL: projection account-redaction fixture requires both custom paths')
    placeholder = '000000000000'
    live_account = '123456789012'
    plan = json.loads(plan_source.read_text(encoding='utf-8'))
    replacements = 0
    policies = {}
    for resource in plan['planned_values']['root_module']['resources']:
        values = resource.get('values')
        policy = values.get('policy') if isinstance(values, dict) else None
        if not isinstance(policy, str):
            continue
        replacements += policy.count(placeholder)
        values['policy'] = policy.replace(placeholder, live_account)
        policies[resource['address']] = values['policy']
    if replacements == 0:
        raise SystemExit('FAIL: projection account-redaction fixture lacks an account')
    role = json.loads(role_source.read_text(encoding='utf-8'))
    projection_hashes = {}
    for projection in role['projection']['roles']:
        raw_policy = projection['policy_document'].replace(placeholder, live_account)
        projection['policy_sha256'] = hashlib.sha256(raw_policy.encode()).hexdigest()
        projection['redacted_policy_sha256'] = hashlib.sha256(
            projection['policy_document'].encode()
        ).hexdigest()
        projection_hashes[projection['projection_id']] = projection['policy_sha256']
        for source_document in projection['source_documents']:
            source_document['sha256'] = hashlib.sha256(
                policies[source_document['address']].encode()
            ).hexdigest()
    for record in role['records']:
        projection_ref = record.get('projection', {})
        projection_id = projection_ref.get('projection_id')
        if projection_id not in projection_hashes:
            continue
        projection_ref['policy_sha256'] = projection_hashes[projection_id]
        put_hashes = record.get('document_hashes_submitted', {}).get('put_role_policy', [])
        if len(put_hashes) == 1:
            put_hashes[0]['sha256'] = projection_hashes[projection_id]
    if custom_source is not None and custom_out is not None:
        custom = json.loads(custom_source.read_text(encoding='utf-8'))
        case_id = (
            'case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:'
            'ALL:aws:RequestTag/Project:matching'
        )
        custom_record = next(
            record for record in custom['records'] if record.get('case_id') == case_id
        )
        role_record = next(
            record for record in role['records'] if record.get('case_id') == case_id
        )
        source_hash = hashlib.sha256(
            policies['aws_iam_policy.deployer_data'].encode()
        ).hexdigest()
        custom_record['document_hashes_submitted']['policy_input_list'][0][
            'sha256'
        ] = source_hash
        role_record['document_hashes_submitted']['custom_lane'][0][
            'sha256'
        ] = source_hash
        custom_out.write_text(
            json.dumps(custom, indent=2, sort_keys=True) + '\n', encoding='utf-8'
        )
        role['custom_report_sha256'] = hashlib.sha256(custom_out.read_bytes()).hexdigest()
    plan_out.write_text(
        json.dumps(plan, indent=2, sort_keys=True) + '\n', encoding='utf-8'
    )
    role_out.write_text(
        json.dumps(role, indent=2, sort_keys=True) + '\n', encoding='utf-8'
    )


def _command_mutate_role_redacted_policy_hash():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    mutation = sys.argv[3]
    payload = json.loads(source_path.read_text(encoding='utf-8'))
    projection = next(
        item for item in payload['projection']['roles']
        if item.get('projection_id') == 'plan-reader:combined'
    )
    if mutation == 'missing':
        projection.pop('redacted_policy_sha256', None)
    elif mutation == 'digest':
        projection['redacted_policy_sha256'] = '0' * 64
    elif mutation == 'document':
        projection['policy_document'] += ' '
    else:
        raise SystemExit(f'FAIL: unknown redacted policy hash mutation: {mutation}')
    destination.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8'
    )


def _command_validate_renderer_role_passing():
    report_path = Path(sys.argv[1])
    case_id = sys.argv[2]
    rendered = report_path.read_text(encoding='utf-8')
    rows = [
        line for line in rendered.splitlines()
        if line.startswith(f'| {case_id} | principal |')
    ]
    if len(rows) != 1 or not rows[0].endswith('| yes |'):
        raise SystemExit(f'FAIL: renderer rejected valid redacted projection hash: {case_id}')


def _command_mutate_renderer_redacted_hash_branch():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    strict = '    if \"recorded_at\" in role:\n'
    mutant = '    if isinstance(projection.get(\"redacted_policy_sha256\"), str):\n'
    if source.count(strict) == 1:
        source = source.replace(strict, mutant, 1)
    elif source.count(mutant) != 1:
        raise SystemExit('FAIL: renderer redacted hash branch mutation anchor changed')
    destination.write_text(source, encoding='utf-8')
    destination.chmod(0o755)


def _command_mutate_core_projection_validation():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    mutation = sys.argv[3]
    if mutation != 'account-redaction':
        raise SystemExit(f'FAIL: unknown projection validation mutation: {mutation}')
    source = source_path.read_text(encoding='utf-8')
    strict = '''        expected_policy_document = redact_report(
            expected["policy_document"], "policy_document"
        )
        if observed.get("policy_document") != expected_policy_document:'''
    mutant = '''        expected_policy_document = redact_report(
            expected["policy_document"], "policy_document"
        )
        if observed.get("policy_document") != expected["policy_document"]:'''
    if source.count(strict) == 1:
        source = source.replace(strict, mutant, 1)
    elif source.count(mutant) != 1:
        raise SystemExit('FAIL: projection account-redaction mutation anchor changed')
    destination.write_text(source, encoding='utf-8')


def _command_mutate_role_projection_source_bytes():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    plan = json.loads(source_path.read_text(encoding='utf-8'))
    address = 'aws_iam_role_policy.plan_reader_deny'
    resource = next(
        item for item in plan['planned_values']['root_module']['resources']
        if item.get('address') == address
    )
    policy = resource['values']['policy']
    if not policy.startswith('{'):
        raise SystemExit('FAIL: projection source-bytes mutation anchor changed')
    resource['values']['policy'] = '{ ' + policy[1:]
    destination.write_text(
        json.dumps(plan, indent=2, sort_keys=True) + '\n', encoding='utf-8'
    )
    print('plan-reader:combined')


def _command_mutate_runbook_legacy_recorded_on():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = source_path.read_text(encoding='utf-8')
    recorded_on = '  --recorded-on 2026-09-10 \\\n'
    if source.count(recorded_on) == 1:
        source = source.replace(recorded_on, '', 1)
    elif 'scripts/iam-simulate-report.sh \\\n' not in source:
        raise SystemExit('FAIL: runbook legacy render mutation anchor changed')
    destination.write_text(source, encoding='utf-8')


def _command_run_runbook_legacy_render():
    runbook_path, custom_path, role_path, out_dir, repo_root = map(
        Path, sys.argv[1:6]
    )
    blocks = re.findall(
        r'```(?:bash)?\n(.*?)\n```',
        runbook_path.read_text(encoding='utf-8'),
        re.DOTALL,
    )
    commands = [
        block for block in blocks
        if block.lstrip().startswith('scripts/iam-simulate-report.sh')
    ]
    if len(commands) != 1:
        raise SystemExit(
            'FAIL: runbook must contain exactly one IAM report render command'
        )
    args = shlex.split(commands[0].replace('\\\n', ' '))
    replacements = {
        '<custom-report.json>': str(custom_path),
        '<role-report.json>': str(role_path),
        'docs/assets': str(out_dir),
    }
    args = [replacements.get(arg, arg) for arg in args]
    env = os.environ.copy()
    env['IAM_SIM_REPORT_REPO_ROOT'] = str(repo_root)
    result = subprocess.run(
        args,
        cwd=repo_root,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        raise SystemExit(result.stdout.rstrip() or 'FAIL: runbook render command failed')
    expected = {'IAM_SIMULATION_REPORT.md', 'IAM_SIMULATION_PROVENANCE.md'}
    observed = {item.name for item in out_dir.iterdir() if item.is_file()}
    if observed != expected:
        raise SystemExit(
            f'FAIL: runbook render command wrote unexpected files: {sorted(observed)}'
        )
    print('PASS: documented legacy IAM report render command executes')


def _command_mutate_renderer_recording():
    custom_source, role_source, custom_out, role_out = map(Path, sys.argv[1:5])
    mutation = sys.argv[5]
    shutil.copyfile(custom_source, custom_out)
    role = json.loads(role_source.read_text(encoding='utf-8'))
    if mutation == 'recorded-at':
        role['recorded_at'] = '2026-09-09T23:59:59Z'
    elif mutation == 'custom-report-binding':
        role['custom_report_sha256'] = '0' * 64
    else:
        raise SystemExit(f'FAIL: unknown renderer recording mutation: {mutation}')
    role_out.write_text(json.dumps(role, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def _command_mutate_generator_commit():
    source_path = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    mutation = sys.argv[3]
    repo_root = Path(sys.argv[4])
    extra_paths = list(map(Path, sys.argv[5:]))
    provenance_destination = destination
    if len(extra_paths) % 2:
        raise SystemExit('FAIL: generator-commit mutation extra paths must be source/destination pairs')
    if mutation == 'unknown':
        replacement = 'f' * 40
    elif mutation == 'stale':
        replacement = subprocess.run(
            ['git', '-C', str(repo_root), 'rev-parse', 'cb461fd^'],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
    else:
        raise SystemExit(f'FAIL: unknown generator-commit mutation: {mutation}')
    for source_path, destination in [
        (source_path, destination), *zip(extra_paths[::2], extra_paths[1::2])
    ]:
        source = source_path.read_text(encoding='utf-8')
        row = re.search(r'(?m)^\| generator commit \| ([0-9a-f]+) \|$', source)
        if row is None:
            raise SystemExit('FAIL: generator-commit mutation lacks generator row')
        destination.write_text(
            source[:row.start(1)] + replacement + source[row.end(1):], encoding='utf-8'
        )
    if extra_paths:
        _replace_provenance_digest(
            provenance_destination,
            'Markdown report sha256',
            hashlib.sha256(extra_paths[1].read_bytes()).hexdigest(),
        )


def _command_validate_readiness_inventory():
    vectors_path = Path(sys.argv[1])
    plan = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
    vectors = [
        {
            'schema_version': envelope['schema_version'],
            'document': envelope['document'],
            'sid': envelope['sid'],
            **case,
        }
        for vector_path in sorted(vectors_path.rglob('*.json'))
        for envelope in [json.loads(vector_path.read_text(encoding='utf-8'))]
        for case in envelope['cases']
    ]
    documents_by_role = {
        'plan-reader': [
            'aws_iam_role_policy.plan_reader_deny',
            'aws_iam_role_policy.plan_reader_state',
        ],
        'deployer': [
            'aws_iam_policy.deployer_data',
            'aws_iam_policy.deployer_ec2',
            'aws_iam_policy.deployer_elb_ecs',
            'aws_iam_policy.deployer_guard',
            'aws_iam_policy.deployer_iam',
            'aws_iam_policy.deployer_state',
        ],
        'publisher': ['aws_iam_role_policy.publisher'],
    }
    policies = {
        resource['address']: resource['values']['policy']
        for resource in plan['planned_values']['root_module']['resources']
        if resource.get('address') in {
            address for addresses in documents_by_role.values() for address in addresses
        }
    }
    effects = {}
    for address, policy in policies.items():
        statements = json.loads(policy)['Statement']
        if isinstance(statements, dict):
            statements = [statements]
        effects[address] = {
            statement['Sid']: statement['Effect'] for statement in statements
        }
    projections = {}
    for role, addresses in documents_by_role.items():
        combined_statements = []
        versions = set()
        for address in addresses:
            policy = json.loads(policies[address])
            versions.add(policy['Version'])
            statements = policy['Statement']
            combined_statements.extend(
                statements if isinstance(statements, list) else [statements]
            )
        combined = json.dumps(
            {'Version': next(iter(versions)), 'Statement': combined_statements},
            separators=(',', ':'),
        )
        specs = [addresses] if len(re.sub(r'\s', '', combined)) <= 10240 else [
            [address] for address in addresses
        ]
        for spec in specs:
            projection_id = f'{role}:combined' if len(specs) == 1 else f'{role}:{spec[0]}'
            projections[projection_id] = spec
    selected = {}
    for projection_id, addresses in projections.items():
        for vector in vectors:
            expect = vector.get('expect', {})
            required = expect.get('matched_sid_required', [])
            decision = expect.get('decision')
            if vector['document'] not in addresses or vector.get('assertion_kind') != 'decision' or not required:
                continue
            if decision == 'allowed':
                qualifies = True
            elif decision == 'explicitDeny':
                qualifies = any(
                    effects[vector['document']].get(sid) == 'Deny' for sid in required
                )
            else:
                qualifies = False
            if qualifies:
                selected[projection_id] = vector
                break
    expected = {
        'plan-reader:combined': 'case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:protected-resource',
        'deployer:aws_iam_policy.deployer_data': 'case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching',
        'deployer:aws_iam_policy.deployer_ec2': 'case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:matching',
        'deployer:aws_iam_policy.deployer_elb_ecs': 'case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:matching',
        'deployer:aws_iam_policy.deployer_guard': 'case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:protected-resource',
        'deployer:aws_iam_policy.deployer_iam': 'case:aws_iam_policy.deployer_iam:DenyDeleteRolePermissionsBoundary:ALL:none:protected-resource',
        'deployer:aws_iam_policy.deployer_state': 'case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:matching',
        'publisher:combined': 'case:aws_iam_role_policy.publisher:EcrAuth:ALL:none:matching',
    }
    observed = {key: value['case_id'] for key, value in selected.items()}
    if observed != expected:
        raise SystemExit(f'FAIL: projection readiness inventory differs: {json.dumps(observed, sort_keys=True)}')
    for projection_id, vector in selected.items():
        if len(_authorization_action_groups(vector['action_names'])) != 1:
            raise SystemExit(f'FAIL: projection readiness case needs more than one request: {projection_id}')
    print('PASS: every role projection has one deterministic Sid-matching readiness case')


def _command_validate_role_propagation():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    call_paths = sorted(Path(sys.argv[2]).glob('*.json'), key=lambda item: int(item.stem))
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    selected_case = sys.argv[3]
    selected_decision = sys.argv[4]
    zero_projection = sys.argv[5]
    expected_attempts = int(sys.argv[6])
    roles = payload.get('projection', {}).get('roles', [])
    if not roles:
        raise SystemExit('FAIL: propagation report contains no projections')
    if selected_case != '-':
        records = payload.get('records', [])
        if [record.get('case_id') for record in records] != [selected_case]:
            raise SystemExit('FAIL: propagation --only report selected the wrong record')
        if records[0].get('expect', {}).get('decision') != selected_decision:
            raise SystemExit('FAIL: propagation --only report selected the wrong decision class')
    seen_projections = set()
    for role in roles:
        projection_id = role['projection_id']
        readiness = role.get('readiness_case', {})
        if not readiness.get('expect', {}).get('matched_sid_required'):
            raise SystemExit(f'FAIL: propagation readiness lacks a required Sid: {projection_id}')
        if role.get('propagation_attempts') != {
            'readback': expected_attempts,
            'probe': expected_attempts,
        }:
            raise SystemExit(f'FAIL: propagation attempts differ: {projection_id}')
        name = role['name']
        put_indexes = [
            index for index, call in enumerate(calls)
            if call[:2] == ['iam', 'put-role-policy']
            and _option(call, '--role-name') == [name]
        ]
        if len(put_indexes) != 1:
            raise SystemExit(f'FAIL: propagation put-role-policy count differs: {projection_id}')
        cursor = put_indexes[0] + 1
        for _ in range(expected_attempts):
            call = calls[cursor]
            if call[:2] != ['iam', 'get-role-policy'] or _option(call, '--role-name') != [name]:
                raise SystemExit(f'FAIL: propagation readback ordering differs: {projection_id}')
            if _option(call, '--policy-name') != [role['policy_name']] or _option(call, '--query') != ['PolicyDocument'] or _option(call, '--output') != ['json']:
                raise SystemExit(f'FAIL: propagation readback call shape differs: {projection_id}')
            cursor += 1
        expected_actions = readiness['action_names']
        expected_resources = readiness['resource_arns']
        expected_context = readiness.get('context_entries', [])
        for _ in range(expected_attempts):
            call = calls[cursor]
            if call[:2] != ['iam', 'simulate-principal-policy']:
                raise SystemExit(f'FAIL: propagation probe ordering differs: {projection_id}')
            source_arn = _option(call, '--policy-source-arn')
            if source_arn != [f'arn:aws:iam::000000000000:role/{name}']:
                raise SystemExit(f'FAIL: propagation probe principal differs: {projection_id}')
            if _option(call, '--action-names') != expected_actions or _option(call, '--resource-arns') != expected_resources:
                raise SystemExit(f'FAIL: propagation probe case differs: {projection_id}')
            context = _option(call, '--context-entries')
            observed_context = json.loads(context[0]) if context else []
            if observed_context != expected_context:
                raise SystemExit(f'FAIL: propagation probe context differs: {projection_id}')
            if _option(call, '--policy-exclusion-list') != ['{"PolicyType":"scp"}']:
                raise SystemExit(f'FAIL: propagation probe did not exclude SCPs: {projection_id}')
            cursor += 1
        seen_projections.add(projection_id)
    if zero_projection != '-':
        record_projections = {
            record.get('projection', {}).get('projection_id')
            for record in payload.get('records', [])
        }
        if zero_projection not in seen_projections or zero_projection in record_projections:
            raise SystemExit('FAIL: zero-selected projection was not independently probed')
    print('PASS: role propagation calls and attempts match the projection readiness cases')


def _command_validate_role_readback_exhaustion():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    call_paths = sorted(Path(sys.argv[2]).glob('*.json'), key=lambda item: int(item.stem))
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    roles = payload.get('projection', {}).get('roles', [])
    attempts = [role.get('propagation_attempts') for role in roles]
    if not attempts or attempts[0] != {'readback': 5, 'probe': 0}:
        raise SystemExit('FAIL: exhausted readback attempts were not recorded')
    if any(item != {'readback': 0, 'probe': 0} for item in attempts[1:]):
        raise SystemExit('FAIL: propagation continued after readback exhaustion')
    if sum(call[:2] == ['iam', 'get-role-policy'] for call in calls) != 5:
        raise SystemExit('FAIL: exhausted readback did not use exactly five attempts')
    if any(call[:2] == ['iam', 'simulate-principal-policy'] for call in calls):
        raise SystemExit('FAIL: readiness probe ran after readback exhaustion')
    print('PASS: exhausted readback records five attempts and stops before probing')


def _command_validate_role_readiness_exhaustion():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    call_paths = sorted(
        Path(sys.argv[2]).glob('*.json'), key=lambda item: int(item.stem)
    )
    calls = [json.loads(path.read_text(encoding='utf-8')) for path in call_paths]
    roles = payload.get('projection', {}).get('roles', [])
    attempts = [role.get('propagation_attempts') for role in roles]
    if not attempts or attempts[0] != {'readback': 1, 'probe': 5}:
        raise SystemExit('FAIL: exhausted readiness attempts were not recorded')
    if any(item != {'readback': 0, 'probe': 0} for item in attempts[1:]):
        raise SystemExit('FAIL: propagation continued after readiness exhaustion')
    if sum(call[:2] == ['iam', 'get-role-policy'] for call in calls) != 1:
        raise SystemExit('FAIL: exhausted readiness did not use one readback attempt')
    if sum(
        call[:2] == ['iam', 'simulate-principal-policy'] for call in calls
    ) != 5:
        raise SystemExit('FAIL: exhausted readiness did not use exactly five attempts')
    print('PASS: exhausted readiness records five attempts after one readback')


def _command_mutate_role_propagation_retry():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    retry_loop = 'for ((attempt = 1; attempt <= 5; attempt++)); do'
    if source.count(root_line) != 1 or source.count(retry_loop) != 2:
        raise SystemExit('FAIL: role propagation retry mutation anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}', 1)
    destination.write_text(source.replace(retry_loop, 'for ((attempt = 1; attempt <= 1; attempt++)); do', 1), encoding='utf-8')
    destination.chmod(493)


def _command_mutate_role_readback_raw():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    output_json = '--policy-name "$POLICY_NAME" --query PolicyDocument --output json'
    output_text = '--policy-name "$POLICY_NAME" --query PolicyDocument --output text'
    strict = """compare_readback_policy() {
  python3 - "$1" "$2" <<'PY_READBACK'
import json
import sys

try:
    observed = json.loads(sys.argv[1])
    submitted = json.loads(sys.argv[2])
except json.JSONDecodeError as exc:
    print(f"inline policy readback is not valid JSON: {exc}")
    raise SystemExit(1)
if observed != submitted:
    print("inline policy readback differs from submitted document")
    raise SystemExit(1)
PY_READBACK
}"""
    mutant = """compare_readback_policy() {
  if [ "$1" = "$2" ]; then
    return 0
  fi
  echo "inline policy readback differs from submitted document"
  return 1
}"""
    current = """    call_capture iam get-role-policy --role-name "$ROLE_NAME" \
      --policy-name "$POLICY_NAME" --query PolicyDocument --output text
    if [ "$CALL_RC" -eq 0 ] && [ "$CALL_OUTPUT" = "$POLICY_DOCUMENT" ]; then
      return 0
    fi
    READBACK_LAST_ERROR=$CALL_ERROR"""
    current_mutant = """    call_capture iam get-role-policy --role-name "$ROLE_NAME" \
      --policy-name "$POLICY_NAME" --query PolicyDocument --output text
    if [ "$CALL_RC" -eq 0 ]; then
      if [ "$CALL_OUTPUT" = "$POLICY_DOCUMENT" ]; then
        return 0
      fi
      READBACK_LAST_ERROR="inline policy readback differs from submitted document"
    else
      READBACK_LAST_ERROR=$CALL_ERROR
    fi"""
    if source.count(root_line) != 1:
        raise SystemExit('FAIL: role readback root anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}', 1)
    if source.count(output_json) == 1 and source.count(strict) == 1:
        source = source.replace(output_json, output_text, 1).replace(strict, mutant, 1)
    elif source.count(current) == 1:
        source = source.replace(current, current_mutant, 1)
    else:
        raise SystemExit('FAIL: role readback mutation anchor changed')
    destination.write_text(source, encoding='utf-8')
    destination.chmod(0o755)


def _command_mutate_role_retry_base_cap():
    source = Path(sys.argv[1]).read_text(encoding='utf-8')
    destination = Path(sys.argv[2])
    root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    strict = """if ! [[ "$retry_base_seconds" =~ ^[0-9]+$ ]] || [ "$retry_base_seconds" -gt 30 ]; then
  echo "FAIL: IAM_SIM_RETRY_BASE_SECONDS must be an integer from 0 through 30" >&2
  exit 2
fi"""
    mutant = """if ! [[ "$retry_base_seconds" =~ ^[0-9]+$ ]]; then
  echo "FAIL: IAM_SIM_RETRY_BASE_SECONDS must be a non-negative integer" >&2
  exit 2
fi"""
    if source.count(root_line) != 1:
        raise SystemExit('FAIL: role retry-base root anchor changed')
    source = source.replace(root_line, f'REPO_ROOT={shlex.quote(sys.argv[3])}', 1)
    if source.count(strict) == 1:
        source = source.replace(strict, mutant, 1)
    elif source.count(mutant) != 1:
        raise SystemExit('FAIL: role retry-base mutation anchor changed')
    destination.write_text(source, encoding='utf-8')
    destination.chmod(0o755)


COMMANDS = {
    'build': build_fixtures, 'fake-aws': _fake_aws, 'table-counts': _table_counts,
    **{name.removeprefix('_command_').replace('_', '-'): value for name, value in tuple(globals().items()) if name.startswith('_command_')},
}
def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        commands = ', '.join(sorted(COMMANDS))
        raise SystemExit(f'FAIL: fixture helper command must be one of: {commands}')
    command = sys.argv[1]
    sys.argv = [sys.argv[0], *sys.argv[2:]]
    COMMANDS[command]()
if __name__ == '__main__': main()
