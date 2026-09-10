# IAM simulation provenance

The IAM simulation artifacts are generated from the JSON lane reports and are never hand-edited.

| Field | Value |
| --- | --- |
| recorded_from | custom-policy report and temporary-role principal-policy report |
| recorded_on | 2026-09-09 |
| generator commit | b3bf107 |
| commands | `TARGET=aws scripts/iam-simulate.sh --plan &lt;terraform-plan.json&gt; --vectors tests/fixtures/iam-simulate/vectors --report &lt;custom-report.json&gt;`<br>`IAM_SIM_LANE_CONFIRM=create-real-iam-resources TARGET=aws scripts/iam-simulate-roles.sh --plan &lt;terraform-plan.json&gt; --vectors tests/fixtures/iam-simulate/vectors --custom-report &lt;custom-report.json&gt; --report &lt;role-report.json&gt; --expect-account &lt;account&gt;`<br>`scripts/iam-simulate-report.sh --custom-report &lt;custom-report.json&gt; --role-report &lt;role-report.json&gt; --out-dir docs/assets` |
| account and region | Free Plan account in `us-east-1`; the rendered account identifier is always `000000000000`. |
| case counts by outcome | custom: 237 passed, 2 failed, 0 runner failures; role: 156 passed, 0 failed, 0 runner failures |

## Exclusions

- 1: AWS-managed ReadOnlyAccess cannot be represented by the inline role-lane projection
- 16: document is not an identity-role binding
- 67: isolated single-statement simulation has no principal equivalent

## Hygiene review (what was actually checked)

Before publication, `scripts/artifact-hygiene.sh` checks both Markdown files for:

- non-placeholder 12-digit account identifiers, including IAM ARN accounts;
- AWS principal and session identifiers, including assumed-role paths;
- request identifier keys and bare UUIDs; and
- the SHA-256 exemption that removes complete 64-hex digests before the account and UUID checks.

No forbidden-value file is supplied by this renderer, so forbid-list matching is not part of this publication check.
