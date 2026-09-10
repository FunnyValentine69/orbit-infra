# Shell contract tests

Evidence gates: LocalStack apply, Stage 1, and the successful in-job Stage 2 allowance/close path are LOCALSTACK-VERIFIED in CI (Phase 4 run 33757937265; post-merge dispatch run 33825140591 from main 9b253b6; stage-claim exclusivity, the pending hand-backs, and prune are fixture-verified only); the nightly AWS sweeper is CODE-ONLY until P0-3b.

`tests/phase3-contracts.sh` requires PyYAML. Its version is pinned as `pyyaml`
in `tools.lock`, read with `scripts/tool-version.sh pyyaml`, and installed
explicitly in the `terraform-plan.yml` gates job before `scripts/gates.sh`.

`tests/sbom-canon.sh` checks that the real-syft-derived fixtures preserve the
creator string and that timestamp-only changes, consistent identifier
renumbering, and reversed package order compare equal. Five separate assertions
require checksum, license, relationship, identifier-swap, and same-name
relationship-switch changes to compare different; a missing optional
relationships array proves null safety. Two fail-closed assertions reject a
missing `spdxVersion` and a
non-array `packages` field, for 14 assertions total.

The phase-3 suite also joins every logical requirements line and requires a hash,
checks the three direct pins and Dockerfile `--require-hashes` flag, and
structurally verifies scan producer order, attestation flags, pinned Trivy
versions, per-mode verifier call sites, weekly cadence, and the 10-day default.
Its extracted verifier runs 22 cases across freshness boundaries, multiple
attestations, malformed envelopes and timestamps, future timestamps, predicate
contents, scanner versions, severity lists, and input range including
leading-zero values. A removed-freshness mutant and flag/version mutations must
be rejected. The call-site check extracts the upstream and public branches of
the deployment-mode case separately and requires one `verify_scan_attestation`
call per selected image in each branch; a fixture that moves every call into the
public branch must fail the upstream assertion. An indented requirements line
that arrives with no open requirement is rejected rather than dropped, and a
scratch copy with an unhashed continuation inserted before the first requirement
must fail.

The sign-images SBOM idempotency guard is also executed, not only pattern-matched: the region from the prior-predicate temp file through its comparison loop is extracted from the workflow, wrapped in a function, and run with a stubbed `cosign` while jq and `scripts/sbom-canon.sh` stay real. Five cases cover a malformed envelope ahead of a valid one (the step must fail with `could not decode attestations`), a failing `cosign verify-attestation` (no prior attestation, so the image is re-attested), a matching prior predicate, and a differing prior predicate; a mutant that restores the streaming `jq -c` decode must exit 0 on the malformed-first stream, which is the killed-mutant proof that the slurped decode is load-bearing.

Run the cleanup regression suite without AWS or LocalStack:

```
bash tests/cleanup-verifier.sh
```

Fixture provenance: a fixture with `recorded_from` was captured from a real
backend (currently LocalStack 2026.8.1 for the task-definition allowance); a
fixture marked `authored` was hand-written from an API or lifecycle contract
and must be replaced by a recorded response once that backend is available. Never
adjust an `authored` fixture to make a predicate pass; record the real
response instead.

The recorded Conftest plan sidecars carry their recording metadata in
`tests/fixtures/conftest/PROVENANCE.md`. A `terraform show -json` document
cannot carry a custom `recorded_from` key, so the recording metadata stays in
that sidecar.

## Phase 5 Conftest policy gate

Run the Conftest regression suite without AWS or LocalStack:

```
bash tests/conftest-gate.sh
```

The suite first runs fixture hygiene against both committed plans, then
requires `conftest verify` to pass all 91 Rego unit tests. It accepts the good
plan without reporting `aws_security_group.alb`, and requires the bad plan to
exit 1 and report `aws_s3_bucket.open`, `aws_s3_bucket.half`,
`aws_s3_bucket.data`, `aws_security_group.open`, `aws_security_group.alb`,
`aws_security_group.zero_lb`, `aws_vpc_security_group_ingress_rule.open`,
`aws_vpc_security_group_ingress_rule.ipv6_open`,
`aws_security_group_rule.legacy_open`, and
`aws_default_security_group.default`. It also requires the bad plan not to
report the protected `aws_s3_bucket.database`. The suite also proves that a
nested true `*_sensitive` marker and a sensitive output are rejected. The
suite reports all 18 cases: `bad-plan.json` was re-recorded from the updated
bad root, and the recorded bad-root plan is denied for
`aws_vpc_security_group_ingress_rule.ipv6_open`. Bucket
protection requires exactly one fully
locked planned block targeted through either one unambiguous whole-resource
configuration reference or an equal known planned bucket name. Reference and
planned-name correlations are unioned, distinct blocks targeting one bucket are
ambiguous, and unreferenced planned blocks with unknown or known-unmatched targets
are denied as unresolvable. Policy selectors accept only managed resources, so data-source
buckets are ignored and data-source load balancers cannot exempt a managed
group. Open, unknown, or prefix-list non-ALB ingress is denied because this
gate cannot prove a managed prefix list safe. Governed resources whose actions
contain `forget` are denied because their protections cannot be verified. For a
known ALB-group ID, a forgotten managed non-rule resource whose `change.before`
contains that ID also revokes the exemption; a fresh-created group has no known
pre-existing ID to match. The ALB exemption requires one distinct group
reference and a planned root application-ALB instance; known planned attachment
IDs must agree. A configuration group address correlates only when exactly one
planned group instance matches; multiple `count`/`for_each` instances fail
closed as ambiguous. Direct
configuration references from a network, gateway, unknown-type, or unplanned
`aws_lb`, other root managed resources, or root module calls revoke the
exemption, as does a matching known group ID anywhere in any managed planned
resource at any module depth. Planned application ALBs and rule-definition
resources are excluded from those consumer checks. Any configuration reference
under another security group's `expressions.ingress` or `expressions.egress`,
whether flattened or nested, is treated as a rule source; planned nested ingress
and egress `security_groups` source values are likewise excluded. Terraform plan
JSON does not serialize locals, so a
fresh-create ALB-group consumer hidden only behind local or other indirection
remains undetectable; this repository's own root attaches the ALB group only to
the ALB, which the live-plan gate checks through direct references.
An unknown attachment must reference exactly the group's whole-resource and
`.id` traversals. A standalone ingress
rule, including an indexed instance, must also plan a known target equal to the
group's known ID, or the rule target and group ID must both be unknown through
that same exact two-traversal set. Condition references and planned literal or
mismatched IDs are denied. Unknown legacy-rule direction is treated as
potentially ingress.

Fixture provenance: `good-plan.json` and `bad-plan.json` in
`tests/fixtures/conftest/` are `recorded_from` LocalStack 2026.8.1 with
Terraform 1.16.0 on 2026-09-04 from `good-root/` and `bad-root/` via
`make record-conftest-fixtures`. Each `terraform show -json` writes to a
temporary file; `scripts/fixture-hygiene.sh` must accept it before it replaces
the tracked fixture. The check rejects `prior_state`, true leaves below `*_sensitive` or
`sensitive_values`, objects marked `"sensitive": true`, non-empty top-level
`variables` because variables must not be serialized into fixtures,
non-placeholder 12-digit numbers, IPv4 literals outside the documented
RFC 1918, unspecified-address, and loopback allowances, and email addresses.
JSON string keys and values are decoded before IPv6 candidates are parsed
with Python's `ipaddress`: the default route, loopback, link-local, unique-local,
unspecified, and `2001:db8::/32` documentation range are allowed, while other
valid IPv6 literals are rejected. Invalid colon-delimited tokens such as digests
are skipped. Fixtures are re-recorded
from those roots, never edited. The real `envs/preview` plan is never committed
because it can carry prior state and sensitive values.

## Preview source and plan contracts

`tests/preview-source-contracts.sh` comment-strips and parses the root preview
Terraform without providers. Five predicates enforce exactly two direct
`aws_security_group.alb` references, service-group-only workload module wiring,
no security-group indirection/read-back/data lookup, no load-balancer data-source
lookup/read-back, or bracket traversal on the protected load-balancer and
security-group resources, the three-entry root
security-group argument allowlist, and the sole statement object's exact two
partition-derived `Resource` entries in the data bucket policy. Quoted-key
bracket traversals are normalized before the general token scans; independently,
each protected resource token (`aws_lb.this`, `aws_security_group.alb`,
`aws_security_group.service`) is matched against a per-token attribute
allowlist, and the token must be immediately followed by `.` plus an allowed
attribute and nothing else that continues the traversal (only a closing
delimiter, comma, whitespace, or end of line may follow), so wrapped
traversals such as `one([aws_lb.this]).security_groups` or
`[aws_security_group.service][0].ingress` fail by construction.
Its 26 scratch-source mutants include the load-balancer data-source read-back
bypass, spaced and computed bracket traversals, a legacy-splat load-balancer
read-back, wrapped `one([...])` and bracket-indexed read-backs, the nested canonical `Resource`
decoy with a local-backed statement resource,
heredoc rejection, exact root-binding multiplicity, and fail-closed `.tf.json`
handling; all must fail their named predicate. The script runs from `make test`.

`tests/preview-plan-contracts.sh <plan.json>` reads a Terraform plan JSON and
uses 20 predicates to assert the `lb-name` and `tg-name` composition, a known
partition in refresh-derived `prior_state`, the `data-bucket-present` requirement
(exactly one `aws_s3_bucket.data` with a non-null, non-empty string
`.values.bucket`), the preview data bucket lifecycle shape (rule id
`data-retention`, a 7-day multipart abort, and a 30-day expiration on current
objects), the complete SSL-only bucket policy document, exactly one
`aws_lb_listener.http` with known non-empty protocol and action strings, and the
absence of HTTPS listeners or HTTP redirect actions. The contract walks child
modules recursively, so resources nested under `child_modules` at any depth are
included alongside root module resources. `tests/preview-plan-mutations.sh
<plan.json>` first requires the unmodified plan to pass, then derives 49
temporary mutants that prove each contract predicate independently rejects its
targeted drift. The naming mutants cover trailing hyphens, 33-character values,
altered environment segments, empty name parts, and over-budget name parts for
both resources; the partition mutants alter the policy ARN partition or remove
the prior-state data source, and listener mutants delete the HTTP listener,
inject HTTPS or redirects, or set the protocol or action type to null. Three of
the 49 mutants are fail-closed input checks (empty, non-JSON, and
missing-`planned_values` plan files) that confirm the contract script rejects
invalid input rather than passing vacuously. Both scripts run in the
`plan-localstack` job immediately after the Conftest live-plan gate.

Sanitized JSON fixtures in `tests/fixtures/cleanup/` record candidate metadata
and exact API `rc`/`stdout`/`stderr` responses. The production predicate layer
consumes the same response shape for recorded and live probes. The suite covers
the 24-entry stale inventory incident, security-group-rule and unknown ARN
handling, VPC endpoint states, exact inactive ECS status, the scoped LocalStack
allowance, the 30-second AWS process boundary and 660-second ECS waiter
boundary, tag-versus-manifest authority, failed delayed and pre-destroy-only tag
observations, zero-exit tag responses with a missing key, null list, string
list, empty stdout, entry missing `ResourceARN`, or numeric `ResourceARN`,
non-zero and malformed cleanup-verifier results, contradictory summaries,
invalid outcome strings, `passed:true` with a live result, and persistence of a
consistent `passed:false` live result before deadline failure, exact ECS
`MISSING`/non-`MISSING`/unconfirmed-empty responses, an absent state file,
required AWS destroy image references and their Terraform forwarding,
zero-exit `DeleteTaskDefinitions` responses that report the requested ARN in
their `failures` array, atomic owner-plus-manifest lease open with one PUT,
same-environment second-open refusal, empty-`--from` refusal,
generation/status-bound Stage 1, exclusive Stage-1 and Stage-2 claims,
expected-generation forwarding into Stage 2 claims, claim-bound manifest writes, duplicate-close refusal, generic-transition
refusal of `closed`, atomic proof-plus-close, force-cleared claim audit,
owner- and generation-bound close refusals, the three-attempt lease limit,
audited force retry, independent Stage 2 attempts and escalation, the
Stage-2 generic-transition guard, cap escalation with CAS-loss refusal, generation
tombstone pruning and reopening, and end-to-end Stage-1 claim release with state
retention. The suite currently reports 40 cases.

`tests/phase3-contracts.sh` separately checks the broader Phase 3 shell and
Makefile contracts, including the LocalStack owner/rerun guards and the
signal-path test below. It also executes both the AWS close and LocalStack
close-and-sweep workflow blocks against controlled lease/close/sweep scripts.
The in-job sweep block must close on attempt three, stop at 20 `closing`
attempts, reject an unexpected status after one attempt, and fail immediately
when the sweep command fails. The suite verifies the observed generation,
status, and owner arguments, derives the two-hour Stage 2 takeover threshold
from the sweeper workflow timeout, checks the PyYAML import guard, and requires
the gates job to install the pinned PyYAML before `scripts/gates.sh`. It runs
`tests/dispatch-ordering-contracts.sh`, whose jq-level probes extract the live
jobs aggregation and timestamp-comparison filters from
`tests/dispatch-ordering.sh`. It also verifies five IPv6 hygiene negative,
decoded-value/key, allowlist, and digest cases. The `iam-matrix-plan` workflow is
parsed structurally and must contain exactly one job: that job owns the sole
LocalStack action and matching `terraform-plan.yml` image/action pins, the sole
bootstrap producer before the sole `make iam-matrix-plan` consumer, the main
branch guard, and a checkout step with credentials persistence disabled; the
workflow also keeps top-level read-only contents permission and never calls the
inventory or contract scripts directly. It verifies that policy-size remains
required by default and moves to the owner-only `plan-localstack` job after its
health wait, and that Conftest is installed before the bootstrap-plan gate,
bootstrap apply, live plan, redacted summary, live-plan gate, and PR comment in
that order. Fork PRs receive the secret-free gates with policy-size explicitly
skipped; owner PRs receive those gates plus the LocalStack-backed policy-size
check. Neither suite starts, stops, or reconfigures LocalStack.

## Demo recording contracts

Run the recorder regression suite without LocalStack, vhs, ffprobe, or network access:

```
bash tests/demo-contracts.sh
```

Its six groups cover the exact per-name environment and unknown-name refusal;
all three tapes and their required output; kind-specific provenance and generator
closures, including ignored Terraform and Rego input refusal; the bounded,
owner- and generation-fenced lease recovery helper; the existing lifecycle
transaction failure table; and fake end-to-end lease and supply-chain recordings.
Lease cases include repeat recording from `closed`, abort and claim states,
terminal foreign-owner refusals, mid-loop manual and Stage 2 claim races, teardown
generation replacement, one- and two-pass sleeps, exhaustion, and an injected
post-inventory display failure proving the no-backend-call boundary. Drift mutants
cover each kind's scripts, templates, contracts, and fixtures. The provenance
commit must be reachable, so CI checks out full history (`fetch-depth: 0`); a
shallow checkout fails with `generator commit unreachable; fetch full history`. The suite
remains chained through `tests/phase3-contracts.sh`.

Run the storyboard generator contracts separately or through `make test`:

```
bash tests/storyboard-contracts.sh
```

The generator group checks exact captions, byte determinism, accessibility,
hygiene, reduced motion, and static snapshot scheduling. It also uses
Git-initialized scratch roots to require the explicit one-missing failure, reject
a tampered SVG even when its local provenance hash matches, and preserve the
both-absent skip branch. Until both committed storyboard outputs exist, the
asset group alone reports
`SKIP: storyboard asset not committed yet`; once present, it validates byte
identity, provenance hash, commit reachability, and the generator closure.

Run the process-group signal test directly without LocalStack:

```
bash tests/localstack-concurrency-signal.sh
```

It starts a fake worker whose process-group leader exits while a descendant
keeps running, sends SIGTERM to the concurrency script, and requires the
descendant to be gone after the exit trap targets the recorded process group
and reaps the recorded worker.

## IAM action-condition matrix

Run source mode without LocalStack:

```
bash tests/iam-matrix-contracts.sh
```

Source mode requires exactly 86 statement rows and 13 binding rows. It verifies
source Sid and document order, all seven condition-operator truth tables and
their prescribed decisions, and exactly one unambiguous `expect <decision>`
clause in every ordinary executable case. Every executable non-KMS `:absent`
variant must omit the tested key: single-condition rows state that no entry is
passed, while multi-condition rows pass only the other satisfying keys. The
wrong-audience trust variant uses its exact conditional provider form and is
`CODE-ONLY`; a bare `N/A(...)` is rejected. Source mode also checks same-action
`resource:nonmatching` cases for every resource-scoped Allow, permits an exact
`N/A(<reason>)` body only for the documented non-executable shapes (including
trust `aud`/`sub` absent variants, the unobtainable mutable-name subject, and
full-type wildcards such as
`hostedzone/*`), rejects unquoted glob characters in simulator option arguments, and validates `stringList` handling for multivalued KMS aliases.
From comment-stripped HCL and canonical matrix
resources it derives same-role Action and conservative Resource overlap across
every other Allow or Deny, including same-document statements. The attached
`ReadOnlyAccess` policy is modeled as covering every `Describe*`, `Get*`, and
`List*` action on `*`. The exact isolated single-statement masked-negative form
is required on all and only the resulting 66 negative cases across 26 Sids;
the isolated policy must name the row Sid, and attribution must identify a
covering source Sid and document or `ReadOnlyAccess`. Every other
executable non-boundary identity case uses principal simulation with its exact
bound-role ARN. Every account-bearing ARN must use the deliberate LocalStack
placeholder account `000000000000`, making the real-account render substitution
total. Boundary cases use custom simulation; live KMS cases name their exact
execution role ARN. The same HCL comment stripper protects Sid inventory and
complete, anchored boundary-assignment counts, so comments and quoted decoys do
not count. Fixture hygiene scans regular files plus symlink target strings and
rejects links that resolve outside the IAM fixture directory. Evidence-label
syntax is checked, but the labels are recorded P0-3d facts whose truth cannot be
validated mechanically. The `absent-key-passed`, `arn-real-account`,
`allow-masked-negative-missing`, `masked-negative-missing`,
`masked-negative-wrong-sid`, `masked-form-on-unmasked-row`,
`masked-form-whole-document`, `trust-absent-executable`,
`trust-mutable-name-executable`, `unquoted-wildcard`,
`uncommented-extra-sid`, and `wrong-audience-bare-na` mutations must print the
`FAIL:` line for the contract they kill; `commented-sid-ignored` must pass.

The wildcard evaluation contract derives every unconditioned
`Resource = "*"` tuple from comment-stripped `bootstrap/roles.tf` and requires
exact equality with the 37-row reference table. Six tuple-set mutations add a
Sid, append an action, remove or fabricate a table row, and alter each duplicate
`EcrAuth` statement independently; three more break the static condition scopes.
The authored `base-plan.json` includes the invalid Lambda-action removal plus the
three conditions and one statement split. Because the bootstrap policy changed,
the host worker must run `make bootstrap-apply TARGET=localstack` followed by
`make iam-matrix-plan` to refresh plan-mode evidence; the fixture was not
presented as a LocalStack recording. A second equality covers the 14 tuples
condition-scoped in this PR: the tuples of the three scoped Sids in
`bootstrap/roles.tf` must equal the rows of the condition-scoped table, each
with both conclusions filled and a follow-up cited where resource scope is
possible, with a removed-row and an appended-action fixture that must fail.

After bootstrap has been applied to LocalStack, render and compare plan mode
through the one hardened render path:

```
make iam-matrix-plan
```

For an already-rendered post-apply plan, run
`bash tests/iam-matrix-contracts.sh <post-apply-plan.json>`. Plan mode compares
Effect, Principal or NotPrincipal, Action or NotAction, Resource or
NotResource, Condition, all bindings, and all three trust documents exactly.
String and array policy fields canonicalise identically. A pre-apply plan whose
trust policies are unknown fails with the apply-first diagnostic. This exact comparison runs in the same-repository `plan-localstack` job and in
`iam-matrix-plan.yml` after a LocalStack bootstrap apply on every push to
`main`, weekly, and by manual dispatch from the default branch. Source mode
remains Sid-keyed on fork PRs; the next main push closes that exact-field drift
window, with the weekly run as a backstop.

The slim plan and hygiene inputs in `tests/fixtures/iam-matrix/` are `authored`;
their sidecar is `tests/fixtures/iam-matrix/PROVENANCE.md`. The condition-key
reordering case asserts byte-identical inventory output. The email-address and
second-account-id cases store safe fragments; the latter also injects the
assembled ID into a temporary copy of `base-plan.json` to prove fixture-tree
scanning without retaining that rejected value.

`tests/policy-size-contracts.sh` has two groups, both running from a per-run
temporary copy of the policy-size script and bootstrap Terraform files so
concurrent suites never write to or delete the repository override. The
existing-override group covers a regular file and a dangling symlink; both
require immediate refusal and zero Terraform invocations, while the regular
sentinel remains byte-identical and the link remains present with its target
string unchanged. The no-existing-override group exercises
init, plan, and show failures plus success, requires cleanup after every path,
and verifies that `POLICY_SIZE_PLAN_JSON_OUT` receives the rendered plan.
A structural contract also requires the override copy to run in a
`set -o noclobber` subshell. This proves the create itself refuses a file that
appears after the fast pre-check, without attempting to schedule that race in
the test.

`tests/bootstrap-override-contracts.sh` applies the same ownership contract to
both Makefile LocalStack bootstrap targets. Its 12 cases cover regular and
dangling operator-owned sentinels with zero Terraform calls, successful
creation and cleanup, directory-backed example-source copy failures that do not
depend on permission bits and occur before any Terraform call, and injected
init/plan/apply failures with their original recipe exit
status and cleanup. It runs from `make test`.

## IAM simulator contracts

Run all eight taxonomy, case-ID, vector-schema, completeness, custom-runner,
role-lane, report-renderer, and Evidence-join contract groups without AWS,
Terraform, Docker, or LocalStack:

```bash
bash tests/iam-simulate-contracts.sh
```

The phase-2 fixture library describes its plans, vector envelopes, canned
simulator responses, custom-report records, and fake role-lane scenarios as
base-plus-override tables in `tests/lib/iam-simulate-fixtures.py`. One generic
renderer materializes every family. The execution registry in
`tests/lib/iam-simulate-mutations.txt` currently names 134 stable mutation case
IDs, their mutation functions or `sed` targets, and their expected `FAIL:`
diagnostic prefixes. The suite records each executed failure, rejects missing,
unregistered, duplicate, or diagnostic-drifting observations, and prints its
executed/registered count only after all restored paths pass.

The shared report writer applies a final recursive identifier redaction, records
`redaction_applied: true`, keeps each top-level summary or scalar on one line,
and renders sorted `records` and role-lane `exclusions` with one compact JSON
object per line. SHA-256 and Git-SHA tokens remain byte-preserved. The `REPORT`
group round-trips this form against the equivalent pretty JSON and kills both a
redaction-removal mutant and an `indent=2` writer mutant before proving the
restored paths. Both simulator lanes use the same writer.

The `REPORT` group executes `scripts/iam-simulate-report.sh` against clean
custom- and role-report fixtures and checks the rendered case table, findings,
divergences, outcome counts, submitted document hashes, provenance, exclusions,
and named hygiene review. A full SHA-256 containing account-shaped digits stays
valid, while the same digits in a case ID fail closed with no published files.
The group also refuses a role report without `account_redacted: true`, checks
both JSON inputs and both rendered Markdown outputs with artifact hygiene, and
kills mutants that remove the role marker guard, the JSON inputs, or the entire
hygiene call. The custom fake validates context entries exactly, and a dropped
`--context-entries` mutant fails. The group also checks that a doctored custom
`pass` cannot suppress a finding. An injected failure
between report and provenance publication restores both original output files;
the provenance is published last. The group also checks the Makefile wiring.
The root `make test` recipe runs
`tests/artifact-hygiene-contracts.sh` immediately after the IAM simulator suite.

The `EVIDENCE` group joins every `AWS-SIMULATED` matrix label to a unique
execution-matching custom-policy record or, when needed, a unique matching
SCP-excluded
role-policy record. It ignores stored custom `pass` values and re-evaluates both
lanes' decisions and required/forbidden Sids against the vector; a runner
failure never matches. It enforces the row minimum, verifies the provenance
date and exact report pointer, and refuses publication date or generator-commit
disagreement between the Markdown report and provenance. It prints the computed
custom, role, and Markdown SHA-256 digests and will compare them once P5-52
makes the renderer record the complete digest set. Twelve registered mutants
cover those joins and bindings, including a doctored SNS pass and a runner
failure. Every restored join must pass.

The `TAXONOMY` group runs
`scripts/iam-simulate-categories.py --check`, independently compares the 288
matrix case IDs to `tests/fixtures/iam-simulate/categories.json`, requires the
four categories to be disjoint with non-empty reasons, and executes added,
removed, duplicate-category, and empty-reason mutations. Regenerate the file
with `python3 scripts/iam-simulate-categories.py`; the stdlib-only generator
parses each row's explicit document and Sid prefix and writes deterministic LF
JSON with array brackets around one compact object per line and a trailing
newline.

The `CASE-ID` group sources `tests/lib/iam-simulate.sh`, round-trips all 288
taxonomy entries, and separately covers `ALL:none`, `ALL:resource`, an
`aws:`-prefixed condition key, a colon-bearing trust document, and wrong-document
refusal. Both runners enforce the same exact-prefix rule instead of splitting
case IDs on colons.

The `SCHEMA` group executes `scripts/iam-simulate-validate.py` against four
positive envelopes covering both simulation modes and assertion kinds, plus
single-defect envelopes for the required failure branches. The files are
synthetic schema fixtures, not authored execution vectors. Their names are
`valid-*.json` and `invalid-*.json`; every invalid fixture is passed to the real
validator and its `FAIL:` diagnostic is asserted. Dedicated cases prove header
prefix and within-envelope duplicate rejection, while `--jsonl` must flatten a
validated envelope by materializing its schema version, document, and Sid.
Embedded `policy_input_list` and `isolated_statement` repository-policy
snapshots remain invalid. The schema is specified in
`docs/iam-simulate-vector-schema.md`. This suite makes no external-service
calls. The validator also accepts a vector directory, validates its 81
envelopes in sorted order in one process, and emits all prepared cases as JSONL;
both execution lanes use that directory form.

The `COMPLETENESS` group reads the 81 real `(document, Sid)` envelopes from
`tests/fixtures/iam-simulate/vectors/`. Filenames are
`<document>__<sid>.json`, with every character outside `[A-Za-z0-9._-]`
replaced by `_`. It counts the 239 case IDs globally, requires every case prefix
to match its envelope header, rejects a case ID appearing in two envelopes,
checks exact filename derivation, and runs the real validator over every
envelope. Simulator-eligible cases must occur exactly once unless
`tests/fixtures/iam-simulate/unresolved.json` records the case ID and a
non-empty precise question. Vectors for either non-simulator category and
unknown case IDs are rejected. Independent mutants remove one `cases` member,
add both forbidden categories, add an unknown ID, duplicate a case across two
envelopes, drift a filename, invalidate one case, mismatch a header, and prove
the counted unresolved exemption.

The `RUNNER` group creates a synthetic plan and vector envelopes in its
temporary workspace, puts a fake `aws` first on `PATH`, and still routes every invocation
through `scripts/aws-cli.sh`. It proves exact-ARN per-resource mapping
when those results exist, action-level decision and attribution for explicit
`*` or an omitted resource list, refusal of missing concrete resource results,
and shared-core-derived separate requests for the two S3 delete names that
require different authorization information. Action-class membership is
case-insensitive, including lower-case
`s3:deletebucketpublicaccessblock`. It also covers 1-based multiline
position-to-Sid
attribution with an exclusive end position and unique overlap against exact
statement spans. The computed two-statement fixture and the exact 5,682-character,
18-statement `deployer_data` plan policy both include the preceding comma in a
returned range; the real `1:1779`/`1:2055` range maps to
`ClickhouseSecretCreateWithTag`. A sibling range overlaps two statements and
must remain ambiguous, while a zero-overlap range remains unmapped; both
refusals assert document-length, span-count, range, and first/last-span
diagnostics. Scanner contracts and killed mutants cover multiline input, braces
and brackets inside a string, escaped quotes, and restoration of strict endpoint
containment. Shared statement scanning also rejects empty and whitespace-only
Sids with the zero-based statement index; an `isinstance`-only mutant is killed
and restored in both execution lanes. Those mutants alter
`scripts/iam_simulate_core.py`, proving the
runner delegates scanning and unique-overlap attribution to the shared module;
the restored module must pass again. The group also covers compatible shared-call
reporting and pre-call
refusal when a duplicate action/resource pair disagrees on its expectation, the
five-attempt throttle cap, timeout non-retry, exact `TARGET=aws` refusal,
byte-equal policy and boundary resolution from raw plan `.values.policy`,
missing-address refusal, and absent/duplicate-Sid refusal before a fake AWS call.
Six table-derived doctored plans independently cover non-array resources,
duplicate addresses, null policies, null role names, invalid suffix names, and
multiple account IDs; each custom-runner guard has a temporary source mutant.
A real-vector contract requires exactly 239 report records and currently counts
8 shared-call batches across 16 cases; mutations make a colliding pair disagree
and drop one shared case from the report. The isolated statement submitted by
the runner comes from the named plan document, and its attribution spans are
computed against that one-statement wrapper. The plan fixture carries all ten
addresses from `scripts/iam-matrix-documents.sh`; no authored execution vectors
are added by this suite.

The `ROLE-LANE` group uses the same fake boundary and stateful temporary role
store. It proves that `custom` vectors are selected unchanged while
`custom-isolated` vectors carry the recorded no-principal-equivalent exclusion.
Custom vectors whose documents are not identity-role bindings are excluded
before custom-report preflight and retain their specific exclusion reason. The
task-boundary fixture proves that such an excluded record may legitimately
contain both the plan-document and synthetic-identity hashes without blocking
the lane. For each selected role it concatenates every mapped document's
`Statement` array in sorted address order. The plan-reader and publisher
projections fit under 10,240 whitespace-stripped characters and use one
combined pass; the six deployer documents do not fit together and therefore
use six separately created, simulated, and deleted per-document roles. Report
records identify the deciding projection with source addresses and SHA-256 hashes.
Before report serialization, one recursive boundary replaces the live account
ID throughout the final object with `000000000000`; reports carry that placeholder in
`account`, replace the per-invocation ownership nonce with `<redacted>`, and set
both redaction markers to `true`. Fake-recorded API calls prove that role names,
trust policies, and principal-policy source ARNs retain the live account ID
while the report contains neither the live account nor the replayable nonce.
Exact `--only` selection executes one case; missing, duplicate, and unsupported
IDs fail with the requested ID and a specific exclusion reason.

An independent projection oracle reconstructs pass partitioning, source order,
concatenated policy bytes, hashes, character counts, case membership, and call
ordering from the Terraform plan and vector envelopes. It does not consume the
role plan emitted by the lane, and source-partition, concatenation, and hash
mutants must each fail it.

The role-lane mapping cases use the same module for the exact 5,682-character
delimiter-inclusive/exclusive-end range, braces and brackets inside strings,
escaped quotes, and an action-level response with no
`ResourceSpecificResults`. The lane prepares its cases once as a NUL-delimited
stream and maps every response in one shared-core invocation per principal
pass, rather than spawning parsers and a mapper per case. The same
strict-containment module mutation must fail both the `RUNNER` and `ROLE-LANE`
groups, followed by an explicit restored pass in each group. Role projection
delegates statement Sid validation to that shared scanner instead of maintaining
a separate type-only check. The six malformed plan shapes are also run against
the role extractor, with a separate guard-neutering source mutant for each
because the two extractors differ. One mutation of the shared action-class
partition likewise makes both lanes submit the rejected
mixed S3 request; the fake returns the matching AWS `InvalidInput` diagnostic,
and both restored lanes must pass.

The group also proves the complete zero-call dry-run inventory, exact opt-in and
account refusals, plus refusal of a plan carrying neither the placeholder nor
the expected account with zero creates. Custom-report mode and source-hash
agreement for selected cases also precede the first create, and selected records
with synthetic identity documents are refused. The principal fake verifies the
exact canonical context-entry set for condition-bearing cases, so a runner that
drops context is killed. Report checks cover both expected- and plan-account
redaction and the `plan_account_redacted` marker. A mutant that moves the custom
preflight back over every loaded vector is killed, while the selected wrong-hash
mutation still records zero create calls. The group also proves both run-id and
32-hex nonce ownership tags before the first policy put, collision isolation,
cleanup after a midway create failure and TERM, the delete-policy barrier,
reverse cleanup across all projection passes, and post-cleanup `NoSuchEntity`
verification. Midway-create and TERM
failures run against both the three-role fixture and the eight-role projection.
Additional eight-role cases inject at deployer p4 between a policy put and its
marker and immediately after policy deletion; cleanup tolerates an unattached policy,
defers TERM until cleanup, absence verification, and report writing finish, and
then returns 143. A nonce-tamper case proves zero policy puts and deletes, and a
nonce-ignoring source mutant is killed. A high-index cleanup mutant still passes
the three-role case but is killed by the eight-role case. The deadline-bounded
full-fixture dry run derives
the projected-role count `R` and selected-case count `C` from the plan and vector
fixtures at run time, then requires exactly `1 + 8R + 2G` calls, where `G` is
the sum of non-empty authorization action groups over the `C` selected cases.
The current full fixture has `R=8`, `C=156`, `G=157`, and therefore 379 calls.
A dropped-call mutant kills the formula check. Its restored path keeps the full
denominator;
the process-substitution descriptor-leak mutant runs against a reduced 24-case
fixture under `ulimit -n 16`, reproducing descriptor exhaustion in seconds
instead of waiting for the former 20-second timeout. Duplicate Sids across
combined role documents and any loaded vector case ID missing from the custom
report fail before a role is created.
Every selected case is simulated first with the exact SCP exclusion and then
with the default effective-policy request. The SCP-excluded decision is compared
to the custom lane's observed decision: disagreement is reportable divergence
evidence, not a failed run. Default-versus-SCP differences are separately
reported per action and resource with Organizations attribution. Every new
contract has a killed mutation whose `FAIL:` line is printed by the suite.

## Phase 5 sweeper fixtures

Run the Stage 2 regression suite without AWS or LocalStack:

```
bash tests/sweeper.sh
```

The suite reuses the repository AWS wrapper with a fake AWS CLI and a fake
versioned S3 lease/state store. It covers every discovery class and age
boundary, invalid inventory IDs, fresh-read Stage 1 selection, retry-budget
and manual-intervention refusal, exact AWS deleted `ClientException` versus
other non-zero describe errors, paginated/batched state-version and
delete-marker removal, `DELETE_IN_PROGRESS`, malformed describe/candidate
refusal, target-scoped LocalStack allowances and missing-allowance refusal,
Stage-1 `passed:false` refusal, present-null version lists, malformed or
incomplete `delete-objects` acknowledgements, zero-exit per-object errors,
post-delete re-list refusal, partial deletion, a lease change between batches,
stale-open generation replacement before Stage 1, exclusive Stage 2 claim and
proof recording, an atomic-completion race that adds a new state version,
stale-claim takeover and audit, young-claim and Stage-1-claim refusals,
classification-to-claim manual escalation, signal release before and after
claim-ending CAS operations, pending-resource hand-back, separate Stage 2
failure accounting, cap escalation, exact state and `.tflock` cleanup with
sibling isolation, an executable single-key selector mutant, prune-time
If-Match loss, and ETag-conditional tombstone replacement, plus a TERM
delivered during a refused Stage-2 takeover claim's own fresh read. The suite
currently reports 39 cases.

Fixture provenance:

- `discover-cases.json` — `authored` from ADR 0006 lifecycle thresholds.
- `aws-deleted-client-exception.json` — `authored` from the AWS ECS deleted
  DescribeTaskDefinition contract; replace with a sanitized recording during
  real-AWS promotion.
- `aws-delete-in-progress.json` — `authored` from the AWS ECS
  `DELETE_IN_PROGRESS` contract.
- `aws-malformed-describe.json` — `authored` fail-closed schema case.
- `localstack-inactive-allowance.json` — `authored` Stage 2 response paired
  with the Stage 1 allowance recorded from LocalStack 2026.8.1; the
  orchestrator replaces it only from a sanitized in-job recording.
- `aws-clientexception-mismatch.json`,
  `aws-inactive-with-localstack-allowance.json`,
  `localstack-inactive-no-allowance.json`, `aws-verification-failed.json`,
  `delete-objects-errors.json`, `list-null-versions.json`,
  `delete-null-entry.json`, `delete-incomplete-ack.json`, and
  `aws-post-delete-relist.json` — `authored` fail-closed branch contracts;
  replace only from sanitized backend recordings that preserve the same
  condition.

## Phase 4 live concurrency

With one already-running LocalStack, an applied LocalStack bootstrap, and the
ARM64 placeholder image present, run:

```
make test-concurrency TARGET=localstack OPERATOR_CIDR=203.0.113.0/24
```

`tests/localstack-concurrency.sh` generates a distinctive `cca...1`/`cca...2`
pair unless `ENV_A` and `ENV_B` are supplied. On that one emulator it proves
lease open/closing refusals and generation stability, overlaps both applies
and both generation-bound closes, checks the isolated `.preview-runs/<id>`
states and ECS cluster names, and queries the module `env_id` tag through
`scripts/aws-cli.sh`. The two filtered ARN sets must be disjoint, and every
returned record must carry exactly one `env_id` tag matching the requested
environment; the ARN text cross-reference check remains an additional guard.
Every record the post-close inventory still lists
(the tagging API is eventually consistent, and LocalStack retains entries for
deleted resources) is evaluated by `scripts/cleanup-verifier.sh` exact probes,
which must report zero live, indeterminate, or pending; the test does not
duplicate the verifier's LocalStack allowance or exact-resource predicates.
Its exit trap closes every lease generation it acquired. Before starting
those closes, the trap terminates
each active apply/close process group and reaps every worker; a failed run
retains only redacted diagnostics.

This local, single-emulator run is the lease-semantics proof. Each hosted
LocalStack workflow run gets a fresh runner and fresh emulator, so separate
GitHub runs cannot observe one another's lease, state, CAS refusal, or
generation increment.

## Phase 4 dispatch ordering

After the change is on `main`, run the LocalStack queue test with:

```
ENV_ID=ord1 TARGET=localstack REF=main bash tests/dispatch-ordering.sh
```

Each invocation generates a nonce, passes a distinct nonce-bearing
`dispatch_note` to all three workflows, and captures exactly one new run whose
display title contains that note, event is `workflow_dispatch`, and head branch
equals `REF`. Both targets require three queue polls with the first apply
in-progress and the second held (`pending`, GitHub's status for a run blocked
by its concurrency group, or `queued`), then observe the destroy held behind it.
After all runs are terminal, the test requires the first apply's latest job
`completed_at` < the second apply's earliest job `started_at`, and the second
apply's latest job `completed_at` < the destroy's earliest job `started_at`.
Equal timestamps are inconclusive and fail closed.
Job timestamps are used because GitHub stamps a run's `run_started_at` when
it accepts the dispatch, before the concurrency group releases the run.
Skipped jobs (for example the destroy job behind a refused validate-input)
are excluded from the aggregation. Before aggregating, each jobs response must
have `total_count` equal to the returned jobs-array length, at least one
non-skipped job, and string `started_at` and `completed_at` values on every
non-skipped job. A response that fails any condition is treated as lagging and
the jobs endpoint is read up to three times ten seconds apart before failing
closed with the condition that remained unsatisfied.

For LocalStack, both applies must conclude `success`; destroy must conclude
`failure` in `validate-input` with the exact `target=localstack` refusal. For
AWS, the first apply and the destroy must conclude `success` and the second
apply must conclude `failure`: per ADR 0006 the first apply leaves its lease
`open`, so the queued second apply is refused at lease open before any
resource is created. The AWS path always
reads the final lease through `TARGET=aws scripts/lease.sh` and requires
the destroy conclusion to be `success` before treating `closing` or `closed`
as safe. Any non-success destroy conclusion, an `open` or `cleanup_failed` lease, an
unreadable status, or invalid ordering leaves cleanup unchecked so the EXIT
trap dispatches one recovery `session-destroy`; the failure names the destroy
run id and observed lease status. Neither target is a cross-run
lease test (each LocalStack run is a fresh emulator). Neither target cancels a
run unless `CANCEL_ON_EXIT=1` is explicitly set.

The session workflows execute jobs only on `main`. Supplying a non-main `REF`
is expected to create a skipped run, so it cannot satisfy this ordering test.
