# IAM simulation provenance

The IAM simulation artifacts are generated from the JSON lane reports and are never hand-edited.

| Field | Value |
| --- | --- |
| recorded_from | custom-policy report and temporary-role principal-policy report |
| recorded_on | 2026-09-12 |
| generator commit | 54a00a2 |
| custom report sha256 | 3442a28690790ce9a2b1d81af0bab08259a202093321811c9c7255f36692119d |
| role report sha256 | 172422dc59a3d95e6b1c24fe7741be7df1b769d911e37d16925b9d54a48eb588 |
| Markdown report sha256 | ea9465bf5cc6a63f6b530eef914c81d0b77a122ee020a684d5c306b0a59a5444 |
| commands | `TARGET=aws scripts/iam-simulate.sh --plan &lt;terraform-plan.json&gt; --vectors tests/fixtures/iam-simulate/vectors --report &lt;custom-report.json&gt;`<br>`IAM_SIM_LANE_CONFIRM=create-real-iam-resources TARGET=aws scripts/iam-simulate-roles.sh --plan &lt;terraform-plan.json&gt; --vectors tests/fixtures/iam-simulate/vectors --custom-report &lt;custom-report.json&gt; --report &lt;role-report.json&gt; --expect-account &lt;account&gt;`<br>`scripts/iam-simulate-report.sh --custom-report &lt;custom-report.json&gt; --role-report &lt;role-report.json&gt; --out-dir docs/assets` |
| account and region | Policy evaluation ran in `us-east-1`; account identifiers are rendered with the placeholder `000000000000`. |
| case counts by outcome | custom: 240 passed, 1 failed, 0 runner failures; role: 158 passed, 0 failed, 0 runner failures |

## Exclusions

- 1: AWS-managed ReadOnlyAccess cannot be represented by the inline role-lane projection
- 16: document is not an identity-role binding
- 67: isolated single-statement simulation has no principal equivalent

## Hygiene review (what was actually checked)

Before publication, `scripts/artifact-hygiene.sh` checks each supplied JSON lane report and both Markdown files for:

- non-placeholder 12-digit account identifiers, including IAM ARN accounts;
- AWS principal and session identifiers, including assumed-role paths;
- request identifier keys and bare UUIDs; and
- field-scoped complete 64/40-hex digest and commit exemptions: JSON digest keys and Markdown digest/commit table cells only.

No forbidden-value file is supplied by this renderer, so forbid-list matching is not part of this publication check.
