# NOTE: verified against the local provider schema (v6.62.0) after
# `terraform init -backend=false`: this provider version uses
# `customer_master_key_spec`, not `key_spec`.
data "aws_iam_policy_document" "signing_key" {
  #checkov:skip=CKV_AWS_109:Account root must retain full key administration; the publisher principal has signing-only actions
  #checkov:skip=CKV_AWS_111:KMS key policies require Resource "*" and are scoped to the key they attach to
  #checkov:skip=CKV_AWS_356:KMS key policies require Resource "*"; access is constrained by the two explicit principals
  statement {
    sid       = "EnableRootAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowPublisherSigning"
    effect    = "Allow"
    actions   = ["kms:Sign", "kms:Verify", "kms:GetPublicKey", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.publisher_role_arn]
    }
  }
}

resource "aws_kms_key" "signing" {
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 30
  policy                   = data.aws_iam_policy_document.signing_key.json

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "signing" {
  name          = "alias/${var.name}-signing"
  target_key_id = aws_kms_key.signing.key_id

  lifecycle {
    prevent_destroy = true
  }
}
