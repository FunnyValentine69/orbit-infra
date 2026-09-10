# IAM simulator vector schema

This document specifies schema version 1 for IAM simulator vector envelopes.
Synthetic contract envelopes live directly under
`tests/fixtures/iam-simulate/`; authored execution envelopes live under its
`vectors/` directory. Each authored file groups all cases for one exact
`(document, Sid)` pair and is named `<document>__<sid>.json`, with every
character outside `[A-Za-z0-9._-]` replaced by `_`.

Validate an envelope with:

```bash
python3 scripts/iam-simulate-validate.py <envelope.json>
```

Add `--jsonl` to emit one flattened JSON object per validated case. Each
flattened object materializes `schema_version`, `document`, and `sid` from the
envelope before the case fields; both runners use that output before `--only`,
batching, and counting.

Each case's `case_id` and assertion kind must agree with the envelope header
and `tests/fixtures/iam-simulate/categories.json`. The required prefix is the
exact string `case:<document>:<sid>:`; case IDs are never split on colons. Only
`simulator-decision` and `simulator-attribution-only` taxonomy entries may have
simulator cases. `live-call-only` and `not-simulatable` entries have no
simulator case. Schema version 1 intentionally has no `notes` case field and
no `principal` vector mode: the matrix row plus exact case ID is the review
linkage, while principal simulation is the separate role-lane projection of
validated `custom` cases.

## Envelope and case fields

Unknown envelope and case fields are invalid. Arrays described as non-empty
must contain unique, non-empty strings. `cases` must be non-empty, and a
`case_id` may occur only once in an envelope.

### Envelope fields

| Field | Type | Requirement |
|---|---|---|
| `schema_version` | integer | Required; exactly `1`. |
| `document` | string | Required; the Terraform resource address whose raw `.values.policy` is resolved from the plan. |
| `sid` | string | Required; the exact statement Sid shared by every case in the envelope. |
| `cases` | non-empty array of objects | Required; cases are sorted by `case_id` in authored envelopes. |

### Case fields

| Field | Type | Requirement |
|---|---|---|
| `case_id` | string | Required; must occur in `categories.json` and start with the envelope's exact `case:<document>:<sid>:` prefix. |
| `simulation_mode` | string enum | Required; `custom` or `custom-isolated`. |
| `assertion_kind` | string enum | Required; `decision` or `attribution-only`, matching the taxonomy category. |
| `permissions_boundary_policy_input_list` | non-empty array of strings | Optional only for `custom`; at most one Terraform resource address. The runner resolves its raw `.values.policy` from the plan. |
| `synthetic_policy_input_list` | non-empty array of strings | Optional only for an `outside-boundary` custom case; exactly one complete synthetic identity-policy string. |
| `action_names` | non-empty array of strings | Required; concrete `service:Action` names with no wildcard. |
| `resource_arns` | array of strings | Required; the exact resources submitted to the simulator, `*`, or an empty array to omit `--resource-arns`. |
| `context_entries` | array of objects | Optional; omit it or use `[]` when no context is submitted. |
| `expect` | object | Required; the assertion described below. |

### Requirements by simulation mode

Both modes require `case_id`, `simulation_mode`, `assertion_kind`,
`action_names`, `resource_arns`, and `expect`. `context_entries` is optional.

| Mode | Additional required fields | Optional mode fields | Forbidden repository-policy snapshots |
|---|---|---|---|
| `custom` | none | `permissions_boundary_policy_input_list`, `synthetic_policy_input_list` for `outside-boundary` only | `policy_input_list`, `isolated_statement` |
| `custom-isolated` | none | none | `policy_input_list`, `permissions_boundary_policy_input_list`, `synthetic_policy_input_list`, `isolated_statement` |

For `custom`, `scripts/iam-simulate.sh` submits the envelope `document`'s full,
byte-exact rendered policy from the plan. No authored case currently needs more
than one repository document. `policy_input_list` is invalid because an inline
copy could drift from that plan.

For `custom-isolated`, the runner parses the same plan-resolved `document`,
selects the only statement whose `Sid` equals the envelope `sid`, and wraps it
as a one-statement policy in `PolicyInputList`. An absent Sid or more than one
matching statement is a hard failure. `isolated_statement` is invalid. This
mode is reserved for masked negative cases and may not expect `allowed`.

The role lane reuses these same `custom` cases. It projects the mapped role
documents and submits each selected case's actions, resources, and context
entries to `simulate-principal-policy`. A `custom-isolated` case is recorded as
excluded because an isolated single-statement simulation has no role
projection equivalent. A `custom` case whose document is not an identity-role
binding, including `aws_iam_policy.task_boundary`, is also recorded as excluded.

`permissions_boundary_policy_input_list` contains plan document addresses, not
policy JSON. All 16 boundary cases name `aws_iam_policy.task_boundary`, whose
raw plan policy is submitted as the permissions boundary. The six
`ALL:none:outside-boundary` cases additionally carry one small inline
`synthetic_policy_input_list` identity Allow for `s3:ListAllMyBuckets`; this is
the sole synthetic-policy exception because that identity policy is not a
repository policy. The IAM request still receives JSON policy strings after
the runner resolves the addresses.

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
## Worked matrix examples

These examples use real case IDs, actions, resources, and expectations from
`docs/iam-matrix.md`. Each is a valid one-case envelope; authored envelopes may
hold multiple cases with the same document and Sid.

### Protected-resource deny

The `DenyReadStateObjectsOutsideScope` row selects an object outside its
`NotResource` exceptions and requires an explicit deny attributed to that Sid.

```json
{
  "schema_version": 1,
  "document": "aws_iam_role_policy.plan_reader_deny",
  "sid": "DenyReadStateObjectsOutsideScope",
  "cases": [
    {
      "case_id": "case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource",
      "simulation_mode": "custom",
      "assertion_kind": "decision",
      "action_names": ["s3:GetObject", "s3:GetObjectVersion"],
      "resource_arns": ["arn:aws:s3:::outside-${SUFFIX}-resource/example"],
      "context_entries": [],
      "expect": {
        "decision": "explicitDeny",
        "matched_sid_required": ["DenyReadStateObjectsOutsideScope"],
        "matched_sid_forbidden": []
      }
    }
  ]
}
```

### `NotResource` exception

The same row's `non-protected-resource` case selects an object inside an
exception. Its assertion is Sid absence, not a decision.

```json
{
  "schema_version": 1,
  "document": "aws_iam_role_policy.plan_reader_deny",
  "sid": "DenyReadStateObjectsOutsideScope",
  "cases": [
    {
      "case_id": "case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource",
      "simulation_mode": "custom",
      "assertion_kind": "attribution-only",
      "action_names": ["s3:GetObject", "s3:GetObjectVersion"],
      "resource_arns": ["arn:aws:s3:::orbit-infra-${SUFFIX}-tfstate/bootstrap/preview"],
      "context_entries": [],
      "expect": {
        "matched_sid_required": [],
        "matched_sid_forbidden": ["DenyReadStateObjectsOutsideScope"]
      }
    }
  ]
}
```

### Condition-key `absent` variant

The `DenyListBucketMissingPrefix` row tests `s3:prefix` absence by submitting no
context entry and expects an explicit deny.

```json
{
  "schema_version": 1,
  "document": "aws_iam_role_policy.plan_reader_deny",
  "sid": "DenyListBucketMissingPrefix",
  "cases": [
    {
      "case_id": "case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:absent",
      "simulation_mode": "custom",
      "assertion_kind": "decision",
      "action_names": ["s3:ListBucket", "s3:ListBucketVersions"],
      "resource_arns": ["arn:aws:s3:::orbit-infra-${SUFFIX}-tfstate"],
      "context_entries": [],
      "expect": {
        "decision": "explicitDeny",
        "matched_sid_required": ["DenyListBucketMissingPrefix"],
        "matched_sid_forbidden": []
      }
    }
  ]
}
```
