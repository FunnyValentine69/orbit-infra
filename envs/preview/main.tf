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
      s3                   = var.localstack_endpoint
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

resource "random_password" "clickhouse" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "clickhouse_password" {
  name = "${var.name}-${var.env_id}-clickhouse-password"

  tags = merge(local.tags, { Name = "${var.name}-${var.env_id}-clickhouse-password" })
}

resource "aws_secretsmanager_secret_version" "clickhouse_password" {
  secret_id     = aws_secretsmanager_secret.clickhouse_password.id
  secret_string = random_password.clickhouse.result
}

module "redis" {
  source = "../../modules/redis"

  providers = {
    aws = aws
  }

  # env_id-prefixed, not var.name-prefixed: modules/ecs-service derives
  # IAM name_prefix as "${var.name}-exec-"/"-task-", capped at 38 chars by
  # AWS; the full "${var.name}-${var.env_id}-clickhouse" project prefix
  # overflows that limit, and env_id alone already disambiguates within
  # this account/region.
  name        = "${var.env_id}-redis"
  env_id      = var.env_id
  cluster_arn = aws_ecs_cluster.this.arn

  subnet_ids         = [module.network.private_subnet_id]
  security_group_ids = [aws_security_group.service.id]

  cloud_map_namespace_id     = aws_service_discovery_private_dns_namespace.this.id
  register_service_discovery = true
  namespace_name             = aws_service_discovery_private_dns_namespace.this.name

  tags = var.tags
}

module "clickhouse" {
  source = "../../modules/clickhouse"

  providers = {
    aws = aws
  }

  name        = "${var.env_id}-clickhouse"
  env_id      = var.env_id
  cluster_arn = aws_ecs_cluster.this.arn

  subnet_ids         = [module.network.private_subnet_id]
  security_group_ids = [aws_security_group.service.id]

  cloud_map_namespace_id     = aws_service_discovery_private_dns_namespace.this.id
  register_service_discovery = true
  namespace_name             = aws_service_discovery_private_dns_namespace.this.name

  password_secret_arn = aws_secretsmanager_secret.clickhouse_password.arn

  tags = var.tags
}

resource "aws_s3_bucket" "data" {
  #checkov:skip=CKV_AWS_144:This platform is ephemeral (ADR 0001); cross-region replication has no purpose for a session-scoped environment
  #checkov:skip=CKV_AWS_145:No KMS key exists in this stack's cost model; default AWS-owned SSE is sufficient for a session-scoped environment
  #checkov:skip=CKV2_AWS_61:No lifecycle policy needed; the bucket is force-destroyed with the rest of the environment
  #checkov:skip=CKV2_AWS_62:No idle budget for event notifications on a session-scoped bucket
  #checkov:skip=CKV_AWS_21:Versioning is intentionally off; ADR 0001 treats this environment as ephemeral
  bucket        = "${var.name}-${var.env_id}-data"
  force_destroy = true

  tags = merge(local.tags, { Name = "${var.name}-${var.env_id}-data" })
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

locals {
  api_bucket_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
      Resource = ["${aws_s3_bucket.data.arn}/*"]
    }]
  })

  # LocalStack task containers reach the emulator over a container-visible
  # endpoint (not localhost) and need dummy static credentials; real AWS
  # tasks resolve everything through the task role instead.
  api_localstack_env = var.target == "localstack" ? {
    AWS_ENDPOINT_URL      = var.localstack_container_endpoint
    AWS_ACCESS_KEY_ID     = "test"
    AWS_SECRET_ACCESS_KEY = "test"
  } : {}

  api_env = merge(
    {
      CLICKHOUSE_HOST    = module.clickhouse.discovery_dns_name
      CLICKHOUSE_PORT    = tostring(module.clickhouse.port)
      REDIS_HOST         = module.redis.discovery_dns_name
      REDIS_PORT         = tostring(module.redis.port)
      PLACEHOLDER_BUCKET = aws_s3_bucket.data.bucket
      AWS_REGION         = var.region
    },
    local.api_localstack_env,
  )
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

  env                   = local.api_env
  task_role_policy_json = local.api_bucket_policy_json

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
