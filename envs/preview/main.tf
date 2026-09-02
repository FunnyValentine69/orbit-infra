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
      ec2                    = var.localstack_endpoint
      servicediscovery       = var.localstack_endpoint
      elasticloadbalancing   = var.localstack_endpoint
      elasticloadbalancingv2 = var.localstack_endpoint
      ecs                    = var.localstack_endpoint
      logs                   = var.localstack_endpoint
      secretsmanager         = var.localstack_endpoint
      iam                    = var.localstack_endpoint
      s3                     = var.localstack_endpoint
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

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-${var.env_id}-alb-"
  description = "ALB ingress from the operator CIDR, egress to the ECS service"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "operator HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }

  tags = merge(local.tags, { Name = "${var.name}-${var.env_id}-alb-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# Separate rule resources (not inline blocks) to avoid a dependency cycle
# between the ALB SG and the service SG, which reference each other.
resource "aws_vpc_security_group_egress_rule" "alb_to_service" {
  security_group_id            = aws_security_group.alb.id
  description                  = "api"
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.service.id

  tags = merge(local.tags, { Name = "${var.name}-${var.env_id}-alb-to-service" })
}

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150:No TLS listener exists per ADR 0004; deletion protection is intentionally off for an ephemeral, Terraform-destroyed environment
  #checkov:skip=CKV_AWS_131:No TLS on this ALB (ADR 0004); drop_invalid_header_fields is the applicable hardening control instead
  name                       = substr("${var.name}-${var.env_id}-alb", 0, 32)
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = module.network.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = merge(local.tags, { Name = "${var.name}-${var.env_id}-alb" })
}

resource "aws_lb_target_group" "api" {
  name        = substr("${var.name}-${var.env_id}-api-tg", 0, 32)
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = module.network.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
  }

  deregistration_delay = 10

  tags = merge(local.tags, { Name = "${var.name}-${var.env_id}-api-tg" })
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:No TLS listener; ADR 0004 (no domain to bind a cert to)
  #checkov:skip=CKV_AWS_103:No TLS, so no TLS-policy applies; see ADR 0004
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_security_group" "service" {
  name_prefix = "${var.name}-${var.env_id}-svc-"
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

  tags = merge(local.tags, { Name = "${var.name}-${var.env_id}-service-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "service_from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "api from ALB"
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id

  tags = merge(local.tags, { Name = "${var.name}-${var.env_id}-service-from-alb" })
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

  name        = "${var.name}-${var.env_id}-redis"
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

  name        = "${var.name}-${var.env_id}-clickhouse"
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
  alb_target_group_arn  = aws_lb_target_group.api.arn

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
