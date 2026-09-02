# NOTE: verified against the local provider schema (v6.62.0) after
# `terraform init -backend=false`: this provider version uses
# `customer_master_key_spec`, not `key_spec`.
resource "aws_kms_key" "signing" {
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 30

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "signing" {
  name          = "alias/${var.name}-signing"
  target_key_id = aws_kms_key.signing.key_id
}
