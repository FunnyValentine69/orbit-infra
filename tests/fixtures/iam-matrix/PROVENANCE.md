# IAM matrix fixture provenance

`base-plan.json` is `authored`. It is a minimized Terraform plan shape derived
from the P5-19 inventory contract and contains only the IAM, KMS-policy, and
binding fields consumed by `scripts/iam-matrix-inventory.sh`. It is not a
backend recording and must not be edited to make a predicate pass.

The hygiene fragments are also `authored`. Tests assemble the fragments in a
temporary directory so the committed repository contains neither an email
address nor a non-placeholder 12-digit account identifier.
