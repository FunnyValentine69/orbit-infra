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
      ec2                  = var.localstack_endpoint
      servicediscovery     = var.localstack_endpoint
      elasticloadbalancing = var.localstack_endpoint
      ecs                  = var.localstack_endpoint
      logs                 = var.localstack_endpoint
      secretsmanager       = var.localstack_endpoint
    }
  }

  default_tags {
    tags = merge(var.tags, { env_id = var.env_id })
  }
}

module "network" {
  source = "../../modules/network"

  providers = {
    aws = aws
  }

  name                       = var.name
  env_id                     = var.env_id
  enable_interface_endpoints = true
  tags                       = var.tags
}
