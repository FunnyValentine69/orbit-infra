# IAM simulator vector schema

This document specifies schema version 1 for IAM simulator vectors. A vector
file contains one JSON object. Synthetic contract fixtures live directly under
`tests/fixtures/iam-simulate/`; authored execution vectors live under its
`vectors/` directory.

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
| `document` | string | Required; must exactly equal the taxonomy entry's `document` and names the Terraform resource address whose raw `.values.policy` is resolved from the plan. |
| `sid` | string | Required; must exactly equal the taxonomy entry's `sid`. |
| `simulation_mode` | string enum | Required; `custom`, `custom-isolated`, or `principal`. |
| `assertion_kind` | string enum | Required; `decision` or `attribution-only`, matching the taxonomy category. |
| `policy_source_arn` | string | Required only for `principal`; the IAM role, user, or group ARN passed as `PolicySourceArn`. |
| `permissions_boundary_policy_input_list` | non-empty array of strings | Optional only for `custom`; at most one Terraform resource address. The runner resolves its raw `.values.policy` from the plan. |
| `synthetic_policy_input_list` | non-empty array of strings | Optional only for an `outside-boundary` custom vector; exactly one complete synthetic identity-policy string. |
| `action_names` | non-empty array of strings | Required; concrete `service:Action` names with no wildcard. |
| `resource_arns` | array of strings | Required; the exact resources submitted to the simulator, `*`, or an empty array to omit `--resource-arns`. |
| `context_entries` | array of objects | Optional; omit it or use `[]` when no context is submitted. |
| `policy_exclusion_list` | non-empty array of objects | Optional only for `principal`; each object is exactly `{"PolicyType":"<type>"}`. |
| `expect` | object | Required; the assertion described below. |
| `notes` | string | Optional. Real vectors under `tests/fixtures/iam-simulate/vectors/` require a non-empty matrix-prose fragment through the completeness contract. It is exact except for the mandatory account and suffix template substitutions described below. |

### Requirements by simulation mode

All modes require the common fields `schema_version`, `case_id`, `document`,
`sid`, `simulation_mode`, `assertion_kind`, `action_names`, `resource_arns`,
and `expect`. `context_entries` is optional in every mode.

| Mode | Additional required fields | Optional mode fields | Forbidden mode fields |
|---|---|---|---|
| `custom` | none | `permissions_boundary_policy_input_list`, `synthetic_policy_input_list` for `outside-boundary` only | `policy_source_arn`, `policy_input_list`, `isolated_statement`, `policy_exclusion_list` |
| `custom-isolated` | none | none | `policy_source_arn`, `policy_input_list`, `permissions_boundary_policy_input_list`, `synthetic_policy_input_list`, `isolated_statement`, `policy_exclusion_list` |
| `principal` | `policy_source_arn` | `policy_exclusion_list` | `policy_input_list`, `permissions_boundary_policy_input_list`, `synthetic_policy_input_list`, `isolated_statement` |

For `custom`, `scripts/iam-simulate.sh` submits the `document` address's full,
byte-exact rendered policy from the plan. No authored vector currently needs
more than one repository document. `policy_input_list` is invalid because an
inline copy could drift from that plan.

For `custom-isolated`, the runner parses the same plan-resolved `document`,
selects the only statement whose `Sid` equals the vector `sid`, and wraps it as
a one-statement policy in `PolicyInputList`. An absent Sid or more than one
matching statement is a hard failure. `isolated_statement` is invalid. This
mode is reserved for masked negative cases and may not expect `allowed`.

The role lane deliberately reuses these same `custom` vectors rather than
maintaining a second set of `principal` vectors. It projects the mapped role
documents and submits each selected vector's existing actions, resources, and
context entries to `simulate-principal-policy`. A `custom-isolated` vector is
recorded as excluded because an isolated single-statement simulation has no
principal equivalent. A `custom` vector whose document is not an identity-role
binding, including `aws_iam_policy.task_boundary`, is also recorded as excluded.
The schema's `principal` mode remains available to other direct-principal
fixtures; it is not the role lane's authored-vector input mode.

`permissions_boundary_policy_input_list` contains plan document addresses, not
policy JSON. All 16 boundary vectors name `aws_iam_policy.task_boundary`, whose
raw plan policy is submitted as the permissions boundary. The six
`ALL:none:outside-boundary` vectors additionally carry one small inline
`synthetic_policy_input_list` identity Allow for `s3:ListAllMyBuckets`; this is
the sole synthetic-policy exception because that identity policy is not a
repository policy. The IAM request still receives JSON policy strings after
the runner resolves the addresses.

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
line and column values. `scripts/iam_simulate_core.py` is the single attribution
implementation used by both runners; each lane sends a response through its
CLI once and maps the source positions back to Sids in the exact submitted
policy text. Line and column are 1-based and the end position is exclusive. A
returned range may include the comma before a statement. Attribution therefore
requires overlap with exactly one statement's half-open span, excluding the
delimiters between statements. No overlap is unmapped, while overlap with two
or more statements is ambiguous; both fail closed with the document length,
span count, returned range, and first and last span in the diagnostic. Statement
spans are located with JSON decoding in the submitted text, not in re-serialized
JSON, so nested braces or brackets inside strings and escaped quotes do not
change the offsets. For `custom-isolated`, attribution uses the submitted
one-statement wrapper rather than the full plan document. Neither runner expects
a nonexistent Sid field in the response.

The top-level `EvalDecision` is aggregate for an action across every submitted
resource, and top-level `EvalResourceName` may be a service template such as
`arn:aws:s3:::${BucketName}/${KeyName}`. When a response carries an exact
submitted ARN in `ResourceSpecificResults`, per-resource assertions use its
decision and matched statements. For a sole `*`, or when `resource_arns` is
empty and the request omits `--resource-arns`, the runner uses the action-level
`EvalDecision` and `MatchedStatements` if no exact resource result exists. It
still refuses absent or incomplete resource-specific results for concrete ARNs.
After rendering, exact submitted ARNs are the keys represented by
`expect.resource_decisions`.

The submitted S3 delete names for bucket ownership controls and public
access block represent delete paths that authorize through
`s3:PutBucketOwnershipControls` and `s3:PutBucketPublicAccessBlock`. The
simulator reports that those two names require different authorization
information from the other actions, so the runner submits that pair separately
and combines the returned action results before evaluation.

## Template rendering

The only vector templates are `${ACCOUNT_ID}` and `${SUFFIX}`. `${ACCOUNT_ID}`
is replaced with the deployed 12-digit account ID. `${SUFFIX}` is replaced with
the deployed project-name suffix represented by `79s5rw` in the matrix; it is
not the taxonomy entry's `suffix` field, which is the remainder of a case ID.

Substitution is literal, recursive across vector string values and object keys,
and must not use shell evaluation. It applies to the permitted synthetic JSON
policy string and `expect.resource_decisions` keys; plan policy text is already
rendered. An unknown `${...}` token is invalid. Any literal 12-digit number
anywhere in a vector file is invalid,
including `000000000000`; use `${ACCOUNT_ID}`. The measured custom-policy
simulator accepts `000000000000`, but committed vectors remain account-neutral.
A real vector's `notes` field quotes its exact matrix case fragment after only
these required normalizations: `000000000000` becomes `${ACCOUNT_ID}` and
`79s5rw` becomes `${SUFFIX}`.

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
