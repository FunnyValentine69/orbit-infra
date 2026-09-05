# ADR 0007: Signing modes and disclosure

Status: Accepted (2026-09-02). Evidence: LOCALSTACK-VERIFIED for apply/close on LocalStack; every real-AWS behavior in this document is CODE-ONLY until the promotion gate P0-3d runs.

## Context

Keyless cosign signing uploads the image reference to the public Rekor
transparency log. Every image distributed by this platform, including the
placeholder built from public source, lives in private ECR. A Rekor upload
would therefore publish the AWS account ID, region, and private ECR repository
name. Those values must never be published; the upstream repository slug is
the one permitted public reference.

## Decision

Every private-ECR image is signed and attested with an asymmetric AWS KMS
key (`awskms://`, the one accepted standing cost, roughly $1/month), using
`--tlog-upload=false` and verification through the exported public key rather
than Rekor. This rule includes the public-source placeholder, the private
upstream images, and the Redis/ClickHouse mirrors. The placeholder's
`placeholder-build/v1` predicate carries only its source commit and build
date. The private images' `local-build/v1` predicate carries only the
upstream commit SHA, the upstream archive hash, the repository-owned
build-input hash, and the build date; it does not claim CI build
provenance. No predicate carries a hostname or account identifier. Cosign's
version is pinned in `tools.lock` and checked before signing. Each SBOM, scan,
signature, and attestation is handled independently on a re-run. Every Trivy
scan explicitly selects the deployed `linux/arm64` image: the action-based
mirror scans set `TRIVY_PLATFORM=linux/arm64`, and the direct CLI scan uses
`--platform linux/arm64`. The placeholder and each mirrored digest must pass
its Trivy scan before that digest is signed or attested, so a first-run scan
failure cannot publish trust metadata for the failed digest.

Before `session-apply.yml` opens a lease, it exports the KMS public key and
verifies all three selected image signatures without contacting Rekor. It then
requires attestations whose predicates match the selected lock-file inputs:
the upstream commit and build-input hashes for locally built images, the
placeholder source commit, and the mirrored source reference and digest. A
missing signature, missing attestation, or predicate mismatch fails before any
lease or preview resource is created. The deployer role grants only the ECR
pull operations and alias-scoped KMS public-key read needed by this gate;
signing remains exclusive to the publisher role.

## Consequences

- All distributed images get signatures and provenance without disclosing
  their private-ECR references.
- Images are verified through the exported KMS public key, not a public Rekor
  lookup.
- Deployment accepts only signed, attested images whose provenance matches the
  lock files, and scans the same `linux/arm64` platform that ECS runs.
- The KMS key is a real, small, standing cost accepted as the price of not disclosing account/repo details.

## Alternatives considered

- **Keyless signing for every image, including private ones:** rejected — discloses account ID, region, and repository names to the public Rekor log.
- **No signing for private images:** rejected — loses the ability to prove an image matches a specific, verified upstream commit.
- **Self-hosted transparency log instead of Rekor:** rejected — adds a persistent service for a guarantee KMS already provides without the disclosure problem.

## Amendment 2026-09-02 (P3-3)

The private upstream images (`orbit-infra-79s5rw/orbit-api`,
`orbit-infra-79s5rw/orbit-worker`, `orbit-infra-79s5rw/orbit-clickhouse`)
are built locally by `scripts/build-upstream.sh`, never in hosted CI: the
build reads only a `git archive` of the pinned, verified upstream commit
(`upstream.lock`), never the working tree, after asserting the local
clone's origin, HEAD, and cleanliness match the lock file. The archive's
sha256 (`upstream_archive_sha256`) is recorded in `upstream.lock`. A second
hash, `repo_build_inputs_sha256`, covers exactly, in order,
`images/clickhouse/Dockerfile`, `scripts/build-upstream.sh`, and the complete
`clickhouse_digest` line from `mirror-images.lock`; these repository-owned
files and the archive are all build inputs. Each image's local content id is
recorded alongside them. Signing is a separate, later step:
`.github/workflows/sign-images.yml` (`workflow_dispatch` only) signs the
already-pushed images with the same asymmetric KMS key described above
(`--tlog-upload=false`, verified via the exported public key), and
attests a `local-build/v1` predicate carrying only the upstream
commit SHA, `upstream_archive_sha256`, `repo_build_inputs_sha256`, and the
signing date — no hostname or
account identifier, and no claim of CI build provenance, since these
images were never built in CI.

## Amendment 2026-09-04: SBOM artifacts and cosign 3.1.3 compatibility

The Tier-3 review of PR #10 found that the `sign-images` workflow previously
uploaded the upstream SBOMs as GitHub Actions artifacts. In a public repository,
those artifacts disclosed private image references and dependency inventories,
contradicting this ADR's non-disclosure rule. The upload step is removed. The
workflow now attests each generated SPDX SBOM to its private image with
`cosign attest --type spdxjson` under the KMS key, with transparency-log upload
disabled. Operators retrieve it with
`cosign verify-attestation --key <exported public key>
--insecure-ignore-tlog --type spdxjson <image@digest> | jq -s '[.[] | .payload |
@base64d | fromjson | select(.predicateType == "https://spdx.dev/Document") |
.predicate] | last' > <name>.spdx.json`. Multiple newline-delimited DSSE
envelopes are possible; this command decodes them and keeps the last matching
SPDX JSON predicate. This path remains `CODE-ONLY` until
P0-3d.

Cosign 3.1.3 requires `--use-signing-config=false` alongside
`--tlog-upload=false`. It also wraps `--type custom` predicates, so the project
now attests with explicit predicate-type URIs:

- `https://github.com/FunnyValentine69/orbit-infra/local-build/v1`
- `https://github.com/FunnyValentine69/orbit-infra/placeholder-build/v1`
- `https://github.com/FunnyValentine69/orbit-infra/mirror/v1`

Verification uses `jq -s` over the per-line DSSE envelopes emitted by
`cosign verify-attestation`. Both facts were found by the PR #11 Tier 1 review
and reproduced against a local registry with a file key. The KMS path remains
`CODE-ONLY` until P0-3d.
