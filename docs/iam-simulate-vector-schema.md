# IAM simulator vector schema

This document specifies schema version 1 for the IAM simulator vectors authored
in a later phase. A vector file contains one JSON object. Phase 1 shipped the
synthetic contract fixtures under `tests/fixtures/iam-simulate/`; Phase 2 adds
the offline-contracted runners, but does not ship the 288 execution vectors.

The validator is:

```bash
python3 scripts/iam-simulate-validate.py <vector.json>
```

The vector's `case_id`, `document`, `sid`, and assertion kind must agree with
`tests/fixtures/iam-simulate/categories.json`. Only
`simulator-decision` and `simulator-attribution-only` taxonomy entries may have
simulator vectors. `live-call-only` and `not-simulatable` entries have no
simulator vector.

## Top-level fields

Unknown fields are invalid. Arrays described as non-empty must contain unique,
non-empty strings.

| Field | Type | Requirement |
|---|---|---|
| `schema_version` | integer | Required in every mode; exactly `1`. |
| `case_id` | string | Required; must occur in `categories.json`. Do not parse it by splitting on colons. |
| `document` | string | Required; must exactly equal the taxonomy entry's `document`. |
| `sid` | string | Required; must exactly equal the taxonomy entry's `sid`. |
| `simulation_mode` | string enum | Required; `custom`, `custom-isolated`, or `principal`. |
| `assertion_kind` | string enum | Required; `decision` or `attribution-only`, matching the taxonomy category. |
| `policy_source_arn` | string | Required only for `principal`; the IAM role, user, or group ARN passed as `PolicySourceArn`. |
| `policy_input_list` | non-empty array of strings | Required only for `custom`. Each item is a string containing a complete JSON IAM policy with a non-empty `Statement`; an object is invalid. |
| `permissions_boundary_policy_input_list` | non-empty array of strings | Optional only for `custom`; at most one complete JSON policy string. |
| `isolated_statement` | object | Required only for `custom-isolated`; forbidden in the other modes. |
| `action_names` | non-empty array of strings | Required; concrete `service:Action` names with no wildcard. |
| `resource_arns` | non-empty array of strings | Required; the exact resources submitted to the simulator, or `*`. |
| `context_entries` | array of objects | Optional; omit it or use `[]` when no context is submitted. |
| `policy_exclusion_list` | non-empty array of objects | Optional only for `principal`; each object is exactly `{"PolicyType":"<type>"}`. |
| `expect` | object | Required; the assertion described below. |

### Requirements by simulation mode

All modes require the common fields `schema_version`, `case_id`, `document`,
`sid`, `simulation_mode`, `assertion_kind`, `action_names`, `resource_arns`,
and `expect`. `context_entries` is optional in every mode.

| Mode | Additional required fields | Optional mode fields | Forbidden mode fields |
|---|---|---|---|
| `custom` | `policy_input_list` | `permissions_boundary_policy_input_list` | `policy_source_arn`, `isolated_statement`, `policy_exclusion_list` |
| `custom-isolated` | `isolated_statement` | none | `policy_source_arn`, `policy_input_list`, `permissions_boundary_policy_input_list`, `policy_exclusion_list` |
| `principal` | `policy_source_arn` | `policy_exclusion_list` | `policy_input_list`, `permissions_boundary_policy_input_list`, `isolated_statement` |

For `custom-isolated`, `isolated_statement` must contain the vector `sid`, an
`Effect` of `Allow` or `Deny`, exactly one of `Action` or `NotAction`, and
exactly one of `Resource` or `NotResource`. `Condition` is optional and must be
an object. `scripts/iam-simulate.sh` wraps this object as
`{"Version":"2012-10-17","Statement":[...]}` and serialize the complete
policy as one JSON string in
`PolicyInputList`. This mode is reserved for masked negative cases and may not
expect `allowed`.

`policy_input_list` and `permissions_boundary_policy_input_list` deliberately
contain JSON strings, not JSON objects. The measured IAM API request shape
accepts each `PolicyInputList` element as a string containing JSON policy text.

For `policy_exclusion_list`, `PolicyType` is lower case and is one of `inline`,
`aws-managed`, `user-managed`, `permission-boundary`, `scp`, or `rcp`. The
measured service-control-policy exclusion is exactly `{"PolicyType":"scp"}`;
the lower-case enum is significant.

## Context entries

Each `context_entries` item has exactly these fields:

| Field | Type | Requirement |
|---|---|---|
| `ContextKeyName` | string | Required and non-empty. |
| `ContextKeyValues` | non-empty array of strings | Required; every value is non-empty. |
| `ContextKeyType` | string enum | Required; one of `string`, `stringList`, `numeric`, `numericList`, `boolean`, `booleanList`, `ip`, `ipList`, `binary`, `binaryList`, `date`, or `dateList`. |

An `absent` case omits the tested key's entire context-entry object. It never
uses an empty `ContextKeyValues` array. Other condition keys required by the
same statement remain present at satisfying values.

## Expectations

`expect` always contains both `matched_sid_required` and
`matched_sid_forbidden`, each an array of unique, non-empty Sid strings. A Sid
cannot occur in both arrays.

| Field | Type | Requirement |
|---|---|---|
| `decision` | string enum | Required for `decision`; forbidden for `attribution-only`. Values are `allowed`, `implicitDeny`, or `explicitDeny`. |
| `matched_sid_required` | array of strings | Required. Every named Sid must be attributed as matched. |
| `matched_sid_forbidden` | array of strings | Required. Every named Sid must be absent from matched attribution. |
| `resource_decisions` | object mapping resource ARN to decision | Optional for a one-resource `decision` vector, required when it has multiple `resource_arns`, and forbidden for `attribution-only`. Its keys must exactly equal `resource_arns`. |

For `assertion_kind: "attribution-only"`, `expect.decision` is absent.
`matched_sid_required` and `matched_sid_forbidden` are the assertion, and at
least one must be non-empty. This represents matrix prose such as `expect not
denied by this statement`, where another effective-policy statement may still
determine the aggregate decision.

The simulator's `MatchedStatements` entries do not contain a Sid. They contain
`SourcePolicyId`, `SourcePolicyType`, `StartPosition`, and `EndPosition` with
line and column values. The custom-lane runner maps those source positions back
to Sids in the exact rendered policy text; it must not expect a nonexistent Sid
field in the response.

The top-level `EvalDecision` is aggregate for an action across every submitted
resource, and top-level `EvalResourceName` may be a service template such as
`arn:aws:s3:::${BucketName}/${KeyName}`. Per-resource assertions must read
`ResourceSpecificResults`, whose `EvalResourceName` is the exact submitted ARN.
After rendering, those exact ARNs are the keys represented by
`expect.resource_decisions`.

## Template rendering

The only vector templates are `${ACCOUNT_ID}` and `${SUFFIX}`. `${ACCOUNT_ID}`
is replaced with the deployed 12-digit account ID. `${SUFFIX}` is replaced with
the deployed project-name suffix represented by `79s5rw` in the matrix; it is
not the taxonomy entry's `suffix` field, which is the remainder of a case ID.

Substitution is literal, recursive across string values and object keys, and
must not use shell evaluation. The same substitution applies to JSON policy
strings and `expect.resource_decisions` keys. An unknown `${...}` token is
invalid. Any literal 12-digit number anywhere in a vector file is invalid,
including `000000000000`; use `${ACCOUNT_ID}`. The measured custom-policy
simulator accepts `000000000000`, but committed vectors remain account-neutral.

## Worked matrix examples

These examples use real case IDs, actions, resources, and expectations from
`docs/iam-matrix.md`; concrete resource names replace the row's prose
placeholders.

### Protected-resource deny

The `DenyReadStateObjectsOutsideScope` row selects an object outside its
`NotResource` exceptions and requires an explicit deny attributed to that Sid.

```json
{
  "schema_version": 1,
  "case_id": "case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource",
  "document": "aws_iam_role_policy.plan_reader_deny",
  "sid": "DenyReadStateObjectsOutsideScope",
  "simulation_mode": "principal",
  "assertion_kind": "decision",
  "policy_source_arn": "arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-plan-reader",
  "action_names": ["s3:GetObject", "s3:GetObjectVersion"],
  "resource_arns": ["arn:aws:s3:::orbit-infra-${SUFFIX}-outside/example.tfstate"],
  "context_entries": [],
  "expect": {
    "decision": "explicitDeny",
    "matched_sid_required": ["DenyReadStateObjectsOutsideScope"],
    "matched_sid_forbidden": []
  }
}
```

### `NotResource` exception

The same row's `non-protected-resource` case selects an object inside the
`envs/preview/*` exception. Its assertion is Sid absence, not a decision.

```json
{
  "schema_version": 1,
  "case_id": "case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource",
  "document": "aws_iam_role_policy.plan_reader_deny",
  "sid": "DenyReadStateObjectsOutsideScope",
  "simulation_mode": "principal",
  "assertion_kind": "attribution-only",
  "policy_source_arn": "arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-plan-reader",
  "action_names": ["s3:GetObject", "s3:GetObjectVersion"],
  "resource_arns": ["arn:aws:s3:::orbit-infra-${SUFFIX}-tfstate/envs/preview/example.tfstate"],
  "context_entries": [],
  "expect": {
    "matched_sid_required": [],
    "matched_sid_forbidden": ["DenyReadStateObjectsOutsideScope"]
  }
}
```

### Condition-key `absent` variant

The `DenyListBucketMissingPrefix` row tests `s3:prefix` absence by submitting no
context entry and expects an explicit deny.

```json
{
  "schema_version": 1,
  "case_id": "case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:absent",
  "document": "aws_iam_role_policy.plan_reader_deny",
  "sid": "DenyListBucketMissingPrefix",
  "simulation_mode": "principal",
  "assertion_kind": "decision",
  "policy_source_arn": "arn:aws:iam::${ACCOUNT_ID}:role/orbit-infra-${SUFFIX}-plan-reader",
  "action_names": ["s3:ListBucket", "s3:ListBucketVersions"],
  "resource_arns": ["arn:aws:s3:::orbit-infra-${SUFFIX}-tfstate"],
  "context_entries": [],
  "expect": {
    "decision": "explicitDeny",
    "matched_sid_required": ["DenyListBucketMissingPrefix"],
    "matched_sid_forbidden": []
  }
}
```
