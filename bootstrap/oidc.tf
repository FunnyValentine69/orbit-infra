# GitHub Actions OIDC provider. Created only when no external provider
# already exists in this account (see preflight.sh classification).
resource "aws_iam_openid_connect_provider" "github" {
  count = var.oidc_provider_external ? 0 : 1

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list intentionally omitted: this provider version (v6.62.0)
  # marks it optional+computed and derives it automatically.

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.oidc_provider_external ? 1 : 0

  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.oidc_provider_external ? data.aws_iam_openid_connect_provider.github[0].arn : aws_iam_openid_connect_provider.github[0].arn
}
