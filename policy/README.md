# policy/

`policy/main.rego` is the Conftest/OPA policy that gates Terraform plan JSON in CI and locally. Run it with `make conftest`, which runs `conftest verify` plus the 19-case recorded-plan regression suite; the tests live in `policy/main_test.rego`, and the plan fixtures it checks against live in `tests/fixtures/conftest` (driven by `tests/conftest-gate.sh`).

## What the Conftest gate denies

Conftest evaluates managed resources only: data-source buckets are not denied,
and data-source groups or load balancers cannot become exemption anchors. It
denies a planned root S3 bucket unless exactly one planned public-access block
targets it through one unambiguous whole-resource configuration reference or an
equal known planned bucket name, has a known planned `after.bucket` equal to the
bucket's known planned name, and enables all four protections. The target set is
the union of reference and planned-name correlation, so distinct blocks targeting
one bucket are ambiguous. A planned block without a bucket reference is denied as
unresolvable when its target is unknown or its known name matches no planned
bucket. Governed resources whose actions contain `forget` are also denied because
their protections cannot be verified. Open, unknown, or prefix-list non-ALB
ingress is denied because this gate cannot prove a managed prefix list safe;
unknown legacy-rule direction is treated as potentially ingress. An ALB exemption
requires exactly one distinct managed security-group reference and a planned root
managed application-ALB instance, with known planned attachment IDs agreeing. A
configuration group address correlates only when exactly one planned group
instance matches; multiple `count`/`for_each` instances fail closed as ambiguous.
Direct configuration references from an `aws_lb` not backed exclusively by known
planned application instances, any other root managed non-rule resource, or a root
module call revoke the exemption. For a group with a known planned ID, a matching
string leaf anywhere in any managed planned `change.after` at any module depth,
or in `change.before` for a forgotten managed non-rule resource, also revokes it.
A fresh-created group has no known pre-existing ID to match. Planned application
ALBs and security-group rule resources are excluded from those consumer checks.
Any configuration reference under another security
group's `expressions.ingress` or `expressions.egress`, whether flattened or nested,
is treated as a rule source rather than a consumer; planned nested ingress or egress
`security_groups` source values are likewise excluded. When an ALB attachment is
unknown, its complete reference set must be exactly the group's whole-resource and
`.id` traversals. A standalone ingress rule, including an indexed instance, must
additionally have one unambiguous group reference and either a known planned
`security_group_id` equal to the group's known planned `id`, or both values unknown
with that same exact two-traversal reference set; condition references and planned
literal or mismatched IDs are denied. The owner-only `plan-localstack` job also
renders and gates the bootstrap plan before bootstrap apply; its state bucket has
all four protections, its block targets `.bucket`, and bootstrap defines no
security groups. The existing gate in `gates` and enforcement on the live
`plan-localstack` PR plan are VERIFIED in CI on PR #12's prior head; the new
bootstrap pre-apply gate and `session-apply` gating of the saved AWS plan remain
CODE-ONLY pending their host/live validation.

## Running the gates

Local, pre-CI policy gates (`.tflint.hcl`, `.checkov.yaml` at repo root):

```
make validate     # terraform init -backend=false + validate, every module/env
make lint         # terraform fmt -check, tflint --recursive, checkov
make test         # terraform test, every module with a tests/ dir (also runs envs/*/tests)
make conftest     # conftest verify + the 19-case recorded-plan regression suite
make test-concurrency TARGET=localstack OPERATOR_CIDR=203.0.113.0/24  # two live environments on one already-running emulator
scripts/gates.sh  # validate -> lint -> test -> docs-contracts -> policy-size -> no-nat-gateway -> conftest, with a PASS/FAIL summary
```

The live concurrency target, its LocalStack-free SIGTERM/process-group test, and the nonce-bound post-merge GitHub dispatch-ordering test are documented in `tests/README.md`; none starts, stops, or reconfigures LocalStack.

`scripts/gates.sh` also requires the `policy-size` gate by default: it renders a LocalStack plan of `bootstrap/` and requires every planned IAM policy document to be plan-time known (see `bootstrap/README.md` § Gates / size). Run it standalone with `bootstrap/policy-size-check.sh`. The secret-free PR gates set `GATES_POLICY_SIZE=skip`; the owner-only `plan-localstack` job runs the check after LocalStack is healthy.
