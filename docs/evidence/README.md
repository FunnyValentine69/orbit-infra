# Evidence index

This directory is the ledger layer for orbit-infra. The four evidence labels and their limits are defined once in [Verification](../VERIFY.md#evidence-labels).

## Evidence table

| Signal | Evidence |
|---|---|
| LocalStack preview lifecycle | `LOCALSTACK-VERIFIED`: bootstrap, apply, service acceptance, Stage 1, and in-job Stage 2 completed in CI; the recordings below preserve the reproducible flows. |
| Lease safety | `LOCALSTACK-VERIFIED` for lifecycle and isolation on one emulator; `fixture-verified` for stale-writer CAS loss, pending hand-back, stale claims, independent retry budgets, and tombstone pruning. |
| Terraform and policy gates | Offline contracts and LocalStack planning cover module tests, source invariants, policy-size limits, documentation, no-NAT topology, and Conftest enforcement. |
| IAM specification | The taxonomy contains 290 cases and the vector set contains 241; 220 cases in 65 matrix rows are `AWS-SIMULATED`. Lower-labelled rows still require their named evidence. |
| IAM simulator publication | The custom lane has 241 results and the role lane has 158 results. The report records policy evaluation, redaction, divergences, and excluded cases; it does not claim service enforcement. |
| Image supply chain | Canonical SBOM, scan freshness, signing, attestation, and apply-side verification are contract-tested; service-backed publication and verification remain `CODE-ONLY`. |
| Pull-request checks | See [PR checks](../VERIFY.md#pull-request-checks) for the required green checks and the intentionally red role-assumption checks. |
| Open work | [TODO.md](../../TODO.md) is the public follow-up ledger. |

## Asset and ledger inventory

| File | Purpose |
|---|---|
| [DEMO_PROVENANCE.md](../assets/DEMO_PROVENANCE.md) | Generator commit, tools, environment, and checks for the lifecycle recording. |
| [DEMO_PROVENANCE_LEASE.md](../assets/DEMO_PROVENANCE_LEASE.md) | Generator and cleanup proof for the lease recording. |
| [DEMO_PROVENANCE_SUPPLYCHAIN.md](../assets/DEMO_PROVENANCE_SUPPLYCHAIN.md) | Generator and canonicalizer proof for the supply-chain recording. |
| [IAM_SIMULATION_PROVENANCE.md](../assets/IAM_SIMULATION_PROVENANCE.md) | Publication metadata and digests joining the IAM reports and renderer. |
| [IAM_SIMULATION_REPORT.md](../assets/IAM_SIMULATION_REPORT.md) | Human-readable custom-policy and role-policy simulator results. |
| [STORYBOARD_PROVENANCE.md](../assets/STORYBOARD_PROVENANCE.md) | Generator commit and deterministic storyboard checks. |
| [demo-lease.gif](../assets/demo-lease.gif) | Recorded owner-bound lease close and state removal. |
| [demo-supplychain.gif](../assets/demo-supplychain.gif) | Recorded canonical SBOM comparison and contracts. |
| [demo.gif](../assets/demo.gif) | Recorded LocalStack plan, policy gate, apply, state, and destroy. |
| [iam-simulation-custom-report.json](../assets/iam-simulation-custom-report.json) | Machine-readable custom-policy simulator results. |
| [iam-simulation-role-report.json](../assets/iam-simulation-role-report.json) | Machine-readable temporary-role simulator results and cleanup record. |
| [storyboard.svg](../assets/storyboard.svg) | Animated overview of pull-request, preview, cleanup, and supply-chain flow. |
| [iam-matrix.md](/docs/evidence/iam-matrix.md) | Authored IAM statements, principal bindings, taxonomy, and evidence cells. |
| [iam-simulate-vector-schema.md](iam-simulate-vector-schema.md) | Schema and validation rules for authored simulator vector envelopes. |
