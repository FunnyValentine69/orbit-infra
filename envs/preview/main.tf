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
      iam                  = var.localstack_endpoint
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

locals {
  tags = merge(var.tags, { env_id = var.env_id })
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-${var.env_id}"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(local.tags, { Name = "${var.name}-${var.env_id}" })
}

resource "aws_service_discovery_private_dns_namespace" "this" {
  name = "${var.env_id}.orbit.internal"
  vpc  = module.network.vpc_id

  tags = merge(local.tags, { Name = "${var.env_id}.orbit.internal" })
}

resource "aws_security_group" "service" {
  name_prefix = "${var.name}-svc-"
  description = "ECS service ingress/egress within the VPC"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "api"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [module.network.vpc_cidr]
  }

  ingress {
    description = "clickhouse"
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = [module.network.vpc_cidr]
  }

  ingress {
    description = "redis"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [module.network.vpc_cidr]
  }

  egress {
    description = "VPC-internal service-to-service traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.network.vpc_cidr]
  }

  egress {
    description     = "Interface VPC endpoints (ECR, Logs, Secrets Manager, ssmmessages)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.network.endpoint_sg_id]
  }

  tags = merge(local.tags, { Name = "${var.name}-service-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

module "api" {
  source = "../../modules/ecs-service"

  providers = {
    aws = aws
  }

  name               = "${var.name}-${var.env_id}-api"
  env_id             = var.env_id
  cluster_arn        = aws_ecs_cluster.this.arn
  image              = var.api_image
  command            = var.api_command
  container_port     = 8000
  subnet_ids         = [module.network.private_subnet_id]
  security_group_ids = [aws_security_group.service.id]

  cloud_map_namespace_id     = aws_service_discovery_private_dns_namespace.this.id
  register_service_discovery = true

  tags = var.tags
}

module "worker" {
  source = "../../modules/ecs-service"

  providers = {
    aws = aws
  }

  enabled = var.worker_image != null

  name               = "${var.name}-${var.env_id}-worker"
  env_id             = var.env_id
  cluster_arn        = aws_ecs_cluster.this.arn
  image              = coalesce(var.worker_image, "unused:unused")
  command            = var.worker_command
  container_port     = 8000
  subnet_ids         = [module.network.private_subnet_id]
  security_group_ids = [aws_security_group.service.id]

  cloud_map_namespace_id     = aws_service_discovery_private_dns_namespace.this.id
  register_service_discovery = true

  tags = var.tags
}
