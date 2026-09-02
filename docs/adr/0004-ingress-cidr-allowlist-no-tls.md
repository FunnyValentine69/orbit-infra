# ADR 0004: Ingress CIDR allowlist, no TLS

Status: Accepted (2026-09-02)

## Context

The ALB is the only path into the private subnet from outside the VPC. The
API behind it (particularly the upstream workload) has no authentication
of its own, so whatever reaches the ALB reaches the API unauthenticated.
There is no domain name for this project, so certificate-based TLS has
nothing to bind to.

## Decision

The ALB security group admits only `operator_cidr`, a required Terraform
variable with no default, over HTTP. Locally this comes from a Makefile
lookup of the operator's public IP; in CI it comes from the repository
**secret** `OPERATOR_CIDR` (not a variable or dispatch input), masked in
public run logs. Every CI apply's first step — before lint, plan, or lease
creation — resolves the runner's own egress address and asserts the
supplied CIDR does not contain it, so a misconfigured allowlist is
rejected before any lease or AWS resource is created. Since the upstream
API has no authentication layer, this allowlist is the only gate.

## Consequences

- No TLS means traffic between operator and ALB is unencrypted; acceptable
  because there is no domain, no persistent secret crosses this path, and
  the operator network is the same trusted network used for the console.
- An overly broad CIDR is not rejected by Terraform itself — the runner-IP
  check only catches the runner-inclusion case; reviewing `operator_cidr`
  before apply stays the operator's responsibility.
- Network changes require `gh secret set OPERATOR_CIDR`; covered in
  RUNBOOKS.md.

## Alternatives considered

- **ACM/self-signed TLS anyway:** rejected — ACM needs a domain to
  validate against, and a self-signed cert just triggers browser warnings.
- **IP allowlist maintained manually in the console:** rejected — defeats
  "everything is Terraform, reviewable," and has no runner-IP check.
- **Add authentication to the API instead:** rejected for the upstream
  workload — this repo doesn't own upstream's application code; filed as
  an upstream issue instead.
