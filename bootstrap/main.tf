provider "aws" {
  region = var.region

  access_key = var.target == "localstack" ? "test" : null
  secret_key = var.target == "localstack" ? "test" : null

  skip_credentials_validation = var.target == "localstack" ? true : null
  skip_metadata_api_check     = var.target == "localstack" ? true : null
  skip_requesting_account_id  = var.target == "localstack" ? true : null
  s3_use_path_style           = var.target == "localstack" ? true : null

  dynamic "endpoints" {
    for_each = var.target == "localstack" ? [1] : []

    content {
      iam = var.localstack_endpoint
      sts = var.localstack_endpoint
      s3  = var.localstack_endpoint
      ecr = var.localstack_endpoint
      kms = var.localstack_endpoint
    }
  }

  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}
