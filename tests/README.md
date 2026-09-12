# Shell contract tests

Evidence labels and publication gates are documented in [Verification](../docs/VERIFY.md). The suites below are contract inventories: each entry names the executable and the behavior it owns.

## Primary entry points

```sh
make test
scripts/gates.sh
bash tests/docs-contracts.sh
env -u AWS_PROFILE bash tests/iam-simulate-contracts.sh
```

`tests/phase3-contracts.sh` requires the PyYAML version pinned in `tools.lock`. Offline suites use fakes and fixtures; they do not make live AWS calls. LocalStack and GitHub dispatch suites state their prerequisites explicitly.

## Documentation contracts

`bash tests/docs-contracts.sh`

The suite scans Markdown links and images in every tracked Markdown file, rejects retired paths both as link targets and as tracked files, and applies a case-insensitive scan to tracked Markdown and shell files for the seven forbidden strings. It enforces the six publication line budgets, requires all four front-page embeds, indexes every file under `docs/assets/` and `docs/evidence/`, and confirms the removed state ledger is untracked. It injects and kills 19 mutations: one budget overflow, one broken link, one retired link target, one bare retired matrix link, one bare retired runbook prose reference, one missing evidence entry, one tracked state ledger, one missing publication file, one tracked retired file, one tracked file missing on disk, one missing front-page embed, all seven forbidden strings, and one lower-case forbidden-string variant. The restored scanner must pass with no skipped publication checks.

## Artifact hygiene

`bash tests/artifact-hygiene-contracts.sh`

This suite exercises the shared hygiene checker against identifiers, account-shaped values, email addresses, paths, tool transcripts, and approved placeholders. Recorded fixtures keep provenance in their adjacent sidecars; generated assets must be regenerated, never hand-edited.

## Bootstrap override contracts

`bash tests/bootstrap-override-contracts.sh`

The 16 cases prove that LocalStack bootstrap plan/apply owns an override only when it creates it. Existing files, symlinks, dangling symlinks, ignored variable files, permission failures, Terraform failures, and cleanup paths must preserve operator-owned entries and avoid unauthorized Terraform calls.

## Conftest policy gate

`bash tests/conftest-gate.sh`

The suite reports 19 cases and also requires all 91 Rego unit tests. It accepts the recorded good plan and rejects the bad plan's public S3 resources, world-open IPv4/IPv6 ingress, ambiguous or unresolvable bucket protection, sensitive plan leaves, and invalid ALB exemptions. Managed resources are evaluated; data sources cannot serve as exemption anchors. The ALB exception requires one unambiguous planned application load balancer attachment, and standalone ingress rules must resolve to the same exact group.

`tests/fixtures/conftest/PROVENANCE.md` records the LocalStack and Terraform versions for `good-plan.json` and `bad-plan.json`. Fixture hygiene rejects prior state, sensitive values, non-empty variables, private identifiers, and non-documentation network literals.

## Preview source and plan contracts

`bash tests/preview-source-contracts.sh`

The source parser checks the exact root data-source multiset, exactly two direct ALB-group references, service-group-only workload wiring, partition-derived data-bucket policy resources, protected-resource traversal allowlists, and exact security-group argument multiplicity. It fails closed on heredocs and `.tf.json`. Its registry contains 29 source mutants, all of which must fail their named predicate before the restored source passes.

`bash tests/preview-plan-contracts.sh <plan.json>`

The plan suite has 20 assertions for bounded load-balancer and target-group names, partition-aware SSL-only data-bucket policy, lifecycle retention, exact HTTP listener shape, and recursive child-module traversal.

`bash tests/preview-plan-mutations.sh <plan.json>`

The mutation suite derives 49 temporary plans, including empty, non-JSON, and missing-`planned_values` fail-closed inputs. Every mutant must fail while the original plan passes.

## Policy-size dispatcher contracts

`bash tests/policy-size-contracts.sh`

Two groups exercise the policy-size check with and without an existing override. The same suite isolates `scripts/gates.sh`, supplies a fake documentation gate, and proves gate order plus failure propagation.

## Phase 3 workflow contracts

`bash tests/phase3-contracts.sh`

This suite covers workflow permissions and guards, pinned tool lookup, placeholder dependency hashes, private-image build and signing order, LocalStack plan and session structure, apply-side Conftest, bounded cleanup, and dispatch contracts. Its extracted scan verifier runs 22 cases; the LocalStack sweep loop runs 4 cases; fixture IPv6 hygiene runs 5 cases. It requires the IAM matrix plan workflow to own exactly one LocalStack bootstrap producer before its exact-field consumer.

`bash tests/sbom-canon.sh`

The canonicalizer reports 14 assertions. Timestamp, identifier renumbering, and package order normalize equal; checksum, license, external-reference, package identity, and relationship changes remain different. Missing schema and invalid package arrays fail closed.

## Cleanup verifier

`bash tests/cleanup-verifier.sh`

The suite reports 55 cases. It covers exact candidate probes, recorded LocalStack allowances, stale tag observations, malformed and contradictory results, timeouts, owner and generation binding, Stage 1 claims, retry limits, force-retry audit, Stage 2 counters, state retention, tombstone generations, and cancellation cleanup. A successful result requires consistent per-candidate outcomes, recomputed counts, and no unexplained live or indeterminate resource.

Fixtures in `tests/fixtures/cleanup/` are either marked `recorded_from` or `authored`. Replace authored fixtures only with sanitized backend recordings that preserve the same contract; never edit one merely to satisfy a predicate.

## Sweeper

`bash tests/sweeper.sh`

The suite reports 41 cases. Its fake versioned S3 and AWS CLI cover classification and age boundaries, exact task-definition outcomes, pagination, per-object delete acknowledgements, partial deletion, stale open replacement, exclusive Stage 2 claims, pending-resource hand-back, independent attempt caps, signal release, stale-claim takeover, state and `.tflock` isolation, CAS loss, and ETag-conditioned tombstone pruning.

## Demo recordings

`bash tests/demo-contracts.sh`

Six groups cover environment construction, tape steps, CIDR and provenance, lease recovery, lifecycle transactions, and lease/supply recordings. The suite uses fakes rather than LocalStack, vhs, ffprobe, or network access. It validates per-kind generator closure, ignored-input refusal, preflight and post-preflight drift, teardown-before-publication, mixed-pair recovery, output metadata, and required provenance fields. Each behavior-changing contract includes a failing mutation before the restored pass.

## Storyboard

`bash tests/storyboard-contracts.sh`

The generator contracts check deterministic keyframes, static snapshots, accessibility, hygiene, and output independence before an asset exists. The asset and provenance checks then bind the committed pair to its recorded generator commit.

## IAM matrix

`bash tests/iam-matrix-contracts.sh`

The matrix inventory contains 86 policy-statement rows and 13 principal bindings. Contracts bind source and exact-plan modes, action/resource/condition cells, trust and KMS principals, wildcard taxonomy, evidence pointers, case identifiers, hashes, and negative fixtures. The matrix is an executable specification; a lower evidence label is not promoted by prose.

## IAM simulator

`env -u AWS_PROFILE bash tests/iam-simulate-contracts.sh`

The taxonomy contains 290 unique cases. The authored vector directory contains 241 cases, and the published Evidence join promotes 220 cases in 65 matrix rows. The mutation registry contains 208 non-comment cases and must dispatch every row, reject no-op actions, observe the expected failure, and restore the changed source or fixture.

The suite is divided into taxonomy, case-ID, schema, completeness, runner, role-lane, renderer, and Evidence groups. It verifies:

- exact vector schema, filename derivation, category coverage, and global case uniqueness;
- shared-core policy hashing, statement scanning, action partitioning, request grouping, response mapping, retries, and fail-closed plan extraction;
- temporary-role projection, exact caller trust, nonce ownership, readback and readiness, reverse cleanup, signal deferral, absence checks, and complete redaction;
- per-action/resource decisions, required and forbidden Sids, principal divergences, Organizations attribution, and projection hashes;
- transactional report publication, artifact hygiene, provenance digests and generator commit, and the 220-case/65-row evidence join.

The role report distinguishes raw `policy_sha256` from `redacted_policy_sha256` for the redacted `policy_document`. Modern reports are keyed by `recorded_at`; missing required digest or redaction fields fail.

The suite uses a fake AWS CLI for runner and temporary-role execution. The committed JSON and Markdown artifacts are sanitized publication inputs; the live invocation procedure is in [Runbooks](../docs/RUNBOOKS.md#iam-simulator-lanes).

## Dispatch and concurrency

`bash tests/dispatch-ordering-contracts.sh`

This offline suite extracts the jq filters used by the live ordering harness and checks complete job arrays, non-skipped timestamps, retry handling, and strict apply-terminal to next-start ordering.

`bash tests/localstack-concurrency-signal.sh`

The signal contract proves the concurrency harness terminates and reaps the full process group even after its leader exits.

`make test-concurrency TARGET=localstack OPERATOR_CIDR=203.0.113.0/24`

With one running emulator, applied LocalStack bootstrap, and ARM64 placeholder image, the live harness overlaps two isolated environments and checks states, tags, clusters, lease refusals, generations, exact cleanup probes, and trap cleanup. It is the single-emulator lease-semantics proof.

`ENV_ID=ord1 TARGET=localstack REF=main bash tests/dispatch-ordering.sh`

After landing on `main`, the live GitHub harness captures nonce-bound apply/apply/destroy runs, waits for the queued chain, compares job timestamps, and enforces target-specific conclusions. LocalStack destroy must refuse because a later runner cannot recover the prior emulator. AWS failures trigger one recovery destroy when final lease safety cannot be confirmed.
