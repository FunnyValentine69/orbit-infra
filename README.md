# orbit-infra

Ephemeral AWS infrastructure for containerized workloads, built with Terraform, ECS Fargate, GitHub Actions OIDC, signed images, and an owner-bound lease lifecycle.

[![terraform-plan](https://github.com/FunnyValentine69/orbit-infra/actions/workflows/terraform-plan.yml/badge.svg)](https://github.com/FunnyValentine69/orbit-infra/actions/workflows/terraform-plan.yml)
![Terraform](https://img.shields.io/badge/IaC-Terraform-844FBA)
![AWS ECS Fargate ARM64](https://img.shields.io/badge/AWS-ECS%20Fargate%20ARM64-FF9900)
![LocalStack](https://img.shields.io/badge/dev%2Fci-LocalStack-6B41F7)

## Why this project exists

Always-on preview infrastructure costs money while it sits unused. orbit-infra creates an isolated environment on demand, verifies it, and removes its resources and state through a guarded two-stage close. The platform is the product: it ships a public placeholder workload and can also deploy the private reference workload `SuperGokou/happyCoding` without publishing that source or its images.

## Highlights

- Three purpose-specific OIDC roles replace static cloud credentials in CI.
- Private tasks run without NAT and reach AWS services through VPC endpoints.
- S3 ETag compare-and-swap protects owner-bound environment leases.
- Terraform, policy, lifecycle, and supply-chain contracts include mutation checks.
- Digest-pinned images require matching signatures, attestations, and fresh scan evidence before AWS apply.

## How a change flows

![Animated storyboard of the change, preview, cleanup, and supply-chain flow](docs/assets/storyboard.svg)

Change-flow storyboard. [Provenance](docs/assets/STORYBOARD_PROVENANCE.md)

![Recorded LocalStack plan, policy gate, apply, state, and destroy](docs/assets/demo.gif)

LocalStack lifecycle recording. [Provenance](docs/assets/DEMO_PROVENANCE.md)

![Recorded owner-bound lease open, close, sweep, and empty state](docs/assets/demo-lease.gif)

Lease lifecycle recording. [Provenance](docs/assets/DEMO_PROVENANCE_LEASE.md)

![Recorded canonical SBOM comparison and contract verification](docs/assets/demo-supplychain.gif)

Supply-chain recording. [Provenance](docs/assets/DEMO_PROVENANCE_SUPPLYCHAIN.md)

## Quickstart (LocalStack)

```sh
make localstack-up
make plan TARGET=localstack ENV_ID=dev
make apply TARGET=localstack ENV_ID=dev
make destroy TARGET=localstack ENV_ID=dev
```

## How it is verified

Claims use four labels: `LOCALSTACK-VERIFIED`, `AWS-SIMULATED`, `CODE-ONLY`, and `fixture-verified`. Static and offline checks run through `terraform-plan.yml`; exact-field IAM matrix planning also runs through `iam-matrix-plan.yml`. [Verification](docs/VERIFY.md) defines the labels, commands, boundaries, and pull-request checks.

## Status

The complete preview lifecycle runs on LocalStack, and real-account IAM policy evaluation is published with its evidence.
The real-AWS deployment tail is out of scope for this portfolio; deployed-service behaviour is verified on LocalStack and IAM policy evaluation with the AWS policy simulator against the real account.

## Documentation map

- [Architecture](ARCHITECTURE.md)
- [Verification](docs/VERIFY.md)
- [Runbooks](docs/RUNBOOKS.md)
- [Threat model](docs/THREAT_MODEL.md)
- `docs/adr/` — architecture decision records
- [Evidence index](docs/evidence/README.md)

## License

MIT, see [LICENSE](LICENSE).
