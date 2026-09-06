# IAM matrix fixture provenance

`base-plan.json` is `authored`. It is a minimized Terraform plan shape derived
from the P5-19 inventory contract and contains only the IAM, KMS-policy, and
binding fields consumed by `scripts/iam-matrix-inventory.sh`. It is not a
backend recording and must not be edited to make a predicate pass.

The hygiene fragments are also `authored`. Tests assemble the fragments in a
temporary directory so the committed repository contains neither an email
address nor a non-placeholder 12-digit account identifier. The account-id test
injects the assembled value into a temporary copy of `base-plan.json` to prove
that fixture-tree hygiene scans JSON as well as Markdown.

The recursive-key-order case is also generated in the temporary directory by
reordering a multi-key Condition in `base-plan.json`; its inventory output must
remain byte-identical to the original fixture.

The masked-negative, statement-isolation, trust-absence, mutable-subject,
shell-quoting, and commented-Sid cases are `authored` mutations generated in a
per-run temporary directory by
`tests/iam-matrix-contracts.sh`. The commented and uncommented Sid mutations use
scratch copies under `IAM_MATRIX_REPO_ROOT`; committed Terraform source is not
modified.
