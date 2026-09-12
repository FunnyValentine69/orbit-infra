# Verification

This page explains how to reproduce the repository checks and how to read its evidence claims. Run commands from the repository root.

## Evidence labels

- **LOCALSTACK-VERIFIED** — executed against the LocalStack emulator, either locally or in CI.
- **AWS-SIMULATED** — evaluated by the AWS policy simulator against the real account; proves IAM policy evaluation, not service enforcement.
- **CODE-ONLY** — implemented and contract-tested, but not executed against the relevant real AWS service.
- **fixture-verified** — exercised through recorded or authored fixtures instead of a live service call.

These labels are deliberately narrow. LocalStack evidence covers emulator-backed Terraform, workflow control flow, lease mutation, lifecycle refusal, and same-job apply and close behavior. It does not prove GitHub OIDC enforcement, AWS service-side condition keys, real ECR or KMS behavior, security-group packet enforcement, AWS Budgets, ECS Exec, or cross-job cleanup. Simulator evidence closes only the policy-evaluation portion of that gap.

The real-AWS deployment tail is out of scope for this portfolio; deployed-service behaviour is verified on LocalStack and IAM policy evaluation with the AWS policy simulator against the real account.

## Visitor checks

Run the offline Terraform and shell contracts:

```sh
make test
```

Run the complete local gate dispatcher:

```sh
scripts/gates.sh
```

The policy-size step needs LocalStack on `http://localhost:4566` (`make localstack-up`); run `GATES_POLICY_SIZE=skip scripts/gates.sh` to omit that step.
The dispatcher runs validation, lint, tests, documentation contracts, IAM policy-size checks, the no-NAT check, and Conftest. The documentation suite checks publication budgets and links, indexes every evidence file, rejects retired paths and private-scope wording, and kills 19 injected mutations before confirming the restored suite.

With LocalStack running and its bootstrap applied, regenerate the exact-field IAM matrix plan:

```sh
make iam-matrix-plan
```

This complements the source-mode inventory by binding action, resource, condition, trust, KMS-principal, statement, and principal rows to a rendered bootstrap plan.

With LocalStack, vhs, FFmpeg, and the placeholder image available, record the lifecycle demonstration:

```sh
make demo
```

The complete front-page set is `make demo`, `make demo NAME=lease`, and `make demo NAME=supply`, or `make demo-all`. Each recorder validates inputs, tears down its environment, renders provenance, and publishes the GIF and provenance as a guarded pair. `make storyboard` deterministically regenerates the SVG and its provenance. The storyboard and recording contracts verify accessibility, hygiene, per-kind generator closure, transaction failure, and drift from the recorded generator commit.

The custom-policy and temporary-role simulator commands, their dry-run boundary, cleanup rules, redaction fields, and report-rendering command are in [IAM simulator lanes](RUNBOOKS.md#iam-simulator-lanes). Those lanes intentionally use the repository wrappers; do not replace them with direct AWS CLI calls.

## What the suites prove

- Tool versions and checksums are pinned in [`tools.lock`](../tools.lock).
- Terraform validation, lint, unit tests, plan policies, preview source contracts, and fail-closed plan mutations run without real AWS credentials.
- Conftest rejects public S3 and unapproved open ingress, checks only managed resources, and permits an ALB security-group exception only when the planned attachment is unambiguous.
- Local concurrency exercises two environments on one emulator, checking isolated state, lease generations and refusals, exact tags, resource verification, and process-group cleanup.
- Dispatch-ordering contracts bind the queued apply/apply/destroy chain and its target-specific conclusions; separate hosted LocalStack runs do not constitute cross-run lease evidence.
- The cleanup verifier records exact candidate outcomes and rejects malformed responses, contradictory summaries, stale writers, owner or generation mismatches, and unverified state deletion.
- The Stage 2 sweeper contracts cover pending deletion, Stage 1 hand-back, independent retry budgets, stale-claim takeover, state and lock removal, CAS loss, and tombstone pruning.
- Supply-chain contracts cover hash-locked dependencies, canonical SBOM comparison, producer ordering, platform-specific scans, predicate freshness, signatures, attestations, and lock-file matching before lease creation.
- The IAM taxonomy, authored vectors, custom-policy lane, role-policy lane, renderer, provenance join, redaction, cleanup, and mutation registry are tested offline. Published `AWS-SIMULATED` results remain policy evaluation, not service enforcement.

The authoritative contract inventory and current suite denominators are in [`tests/README.md`](../tests/README.md). Published reports, JSON records, recordings, and provenance are indexed in the [evidence ledger](evidence/README.md).

## Pull-request checks

`gates` must be green on every pull request. For same-repository pull requests authored by the repository owner, `plan-localstack` and `infracost` must also be green. `gates` is secret-free; the other two use their narrowly scoped service credentials without AWS role assumption.

The `oidc-smoke.yml` workflow has `decode-subject` plus three `assume-*` jobs. All four skip fork pull requests and runs by `dependabot[bot]`. On other same-repository pull requests, each `assume-*` check is expected to stop red at its initial `Require AWS_ROLE_*` step because the real-account role ARN secrets have not been published. If those values are later published, the checks instead prove that pull-request and non-main tokens cannot assume the main-ref-only roles.

The `iam-matrix-plan.yml` workflow applies the LocalStack bootstrap and runs exact-field plan mode after changes reach `main`, on its weekly schedule, or by default-branch dispatch. This closes the field-level drift window that secret-free fork checks cannot close.

## Runtime checks and SLO

The hosted LocalStack session waits for each enabled ECS service to reach its applied task definition, probes the ALB, performs owner-bound Stage 1, and completes Stage 2 in the same job. A later runner cannot recover that emulator, so `session-destroy` refuses a LocalStack target. Recovery procedures are in [Runbooks](RUNBOOKS.md).

For an AWS session, run these commands from a network inside `operator_cidr`; the hosted runner is intentionally outside that CIDR and proves only the negative case (connection refusal or timeout):

```bash
curl -fsS "$ALB_URL/health"
curl -fsS "$ALB_URL/s3-roundtrip"
```

The separate AWS close retains state in `closing` until the sweeper verifies asynchronous deletion and removes every state version.

The written availability objective is at least 99% healthy-host time during an eight-hour session, a 4.8-minute error budget. `UnHealthyHostCount` supplies the measurement and `HTTPCode_Target_5XX_Count` is the leading indicator. LocalStack creates the alarms but has no metric pipeline, so their state remains `INSUFFICIENT_DATA`.
