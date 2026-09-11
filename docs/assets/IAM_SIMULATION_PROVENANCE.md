# IAM simulation provenance

The IAM simulation artifacts are generated from the JSON lane reports and are never hand-edited.

| Field | Value |
| --- | --- |
| recorded_from | custom-policy report and temporary-role principal-policy report |
| recorded_on | 2026-09-11 |
| generator commit | c8d5f87 |
| custom report sha256 | a32624f4c158fbdedb5bfd37eed2e5efa738462a137ffd737af70f960a6cd34d |
| role report sha256 | 08a2165c886d49e4c866c2877623ac9a3e13646067d1a7953300f85f59069d3c |
| Markdown report sha256 | 5898abe5f9fe3189a6e1d0e2fa0fac9f5c7bd9957fcdf5bfb5ad2c5a6a1b912b |
| commands | `TARGET=aws scripts/iam-simulate.sh --plan &lt;terraform-plan.json&gt; --vectors tests/fixtures/iam-simulate/vectors --report &lt;custom-report.json&gt;`<br>`IAM_SIM_LANE_CONFIRM=create-real-iam-resources TARGET=aws scripts/iam-simulate-roles.sh --plan &lt;terraform-plan.json&gt; --vectors tests/fixtures/iam-simulate/vectors --custom-report &lt;custom-report.json&gt; --report &lt;role-report.json&gt; --expect-account &lt;account&gt;`<br>`scripts/iam-simulate-report.sh --custom-report &lt;custom-report.json&gt; --role-report &lt;role-report.json&gt; --out-dir docs/assets` |
| account and region | Free Plan account in `us-east-1`; the rendered account identifier is always `000000000000`. |
| case counts by outcome | custom: 239 passed, 1 failed, 0 runner failures; role: 157 passed, 0 failed, 0 runner failures |

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
