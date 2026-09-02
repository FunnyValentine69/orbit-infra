# ADR 0007: Signing modes and disclosure

Status: Accepted (2026-09-02)

## Context

Keyless cosign signing uploads the image reference to the public Rekor transparency log. For the public placeholder that's the point. For the private upstream images, the same upload would publish the AWS account ID, region, and private ECR repository names — information this project's rules require never be disclosed.

## Decision

Two signing modes, matched to what each image can disclose. The **public placeholder** is signed keyless with cosign, uploaded to Rekor, identity and issuer pinned on verify, attested with `actions/attest-build-provenance` since it really is built in CI. The **private upstream images** are signed with an asymmetric AWS KMS key (`awskms://`, the one accepted standing cost, roughly $1/month) using `--tlog-upload=false`, verified with the exported public key instead of Rekor lookup. No predicate for either mode carries a hostname or account identifier; the private images' `local-build/v1` predicate carries only the upstream commit SHA, the build-input hash (sha256 of the `git archive` of that commit — the only input any private build ever reads), and the build date. It does not claim CI build provenance, since it wasn't built in CI. Cosign's version is pinned in `tools.lock` and checked against `cosign version` before every signing step. Signing verifies first, so a re-run is a no-op.

## Consequences

- The placeholder gets full, independently-verifiable transparency; the private images get provenance without disclosure.
- Private images can't be verified via public Rekor lookup — only via the exported KMS public key, distributed with verification instructions.
- The KMS key is a real, small, standing cost accepted as the price of not disclosing account/repo details.

## Alternatives considered

- **Keyless signing for every image, including private ones:** rejected — discloses account ID, region, and repository names to the public Rekor log.
- **No signing for private images:** rejected — loses the ability to prove an image matches a specific, verified upstream commit.
- **Self-hosted transparency log instead of Rekor:** rejected — adds a persistent service for a guarantee KMS already provides without the disclosure problem.
