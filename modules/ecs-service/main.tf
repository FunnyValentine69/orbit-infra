locals {
  enabled    = var.enabled ? 1 : 0
  is_enabled = var.enabled

  tags = merge(var.tags, { env_id = var.env_id })

  has_secrets = length(var.secrets) > 0

  secrets_list = [
    for secret_name, secret_arn in var.secrets : {
      name      = secret_name
      valueFrom = secret_arn
    }
  ]

  env_list = [
    for env_name, env_value in var.env : {
      name  = env_name
      value = env_value
    }
  ]

  container_definition = merge(
    {
      name         = var.name
      image        = var.image
      essential    = true
      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
      environment  = local.env_list
      secrets      = local.secrets_list
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = try(aws_cloudwatch_log_group.this[0].name, "")
          "awslogs-region"        = try(data.aws_region.current[0].region, "")
          "awslogs-stream-prefix" = var.name
        }
      }
    },
    var.command != null ? { command = var.command } : {},
    var.health_check != null ? {
      healthCheck = {
        command     = var.health_check.command
        interval    = var.health_check.interval
        timeout     = var.health_check.timeout
        retries     = var.health_check.retries
        startPeriod = var.health_check.start_period
      }
    } : {}
  )
}

data "aws_region" "current" {
  count = local.enabled
}

resource "aws_cloudwatch_log_group" "this" {
  count = local.enabled

  #checkov:skip=CKV_AWS_338:This platform is ephemeral (ADR 0001); a 1-year minimum retention has no purpose for a session-scoped environment, so retention stays a short caller-set default
  #checkov:skip=CKV_AWS_158:No KMS key exists in this stack's cost model for log encryption at rest; CloudWatch Logs are already encrypted with AWS-owned keys by default
  name              = "/orbit/${var.env_id}/${var.name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = "/orbit/${var.env_id}/${var.name}" })
}

locals {
  ecs_tasks_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "execution" {
  count = local.enabled

  name_prefix        = "${var.name}-exec-"
  assume_role_policy = local.ecs_tasks_assume_role_policy

  tags = merge(local.tags, { Name = "${var.name}-execution-role" })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  count = local.enabled

  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = local.is_enabled && local.has_secrets ? 1 : 0

  name = "${var.name}-secrets"
  role = aws_iam_role.execution[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = values(var.secrets)
    }]
  })
}

resource "aws_iam_role" "task" {
  count = local.enabled

  name_prefix        = "${var.name}-task-"
  assume_role_policy = local.ecs_tasks_assume_role_policy

  tags = merge(local.tags, { Name = "${var.name}-task-role" })
}

resource "aws_iam_role_policy" "task_exec_command" {
  count = local.is_enabled && var.enable_execute_command ? 1 : 0

  name = "${var.name}-exec-command"
  role = aws_iam_role.task[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "task_custom" {
  count = local.is_enabled && var.task_role_policy_json != null ? 1 : 0

  name   = "${var.name}-custom"
  role   = aws_iam_role.task[0].id
  policy = var.task_role_policy_json
}

resource "aws_ecs_task_definition" "this" {
  count = local.enabled

  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution[0].arn
  task_role_arn            = aws_iam_role.task[0].arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([local.container_definition])

  tags = merge(local.tags, { Name = "${var.name}-task" })
}

resource "aws_service_discovery_service" "this" {
  count = local.is_enabled && var.register_service_discovery ? 1 : 0

  name = var.name

  dns_config {
    namespace_id = var.cloud_map_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  tags = merge(local.tags, { Name = "${var.name}-discovery" })
}

resource "aws_ecs_service" "this" {
  count = local.enabled

  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this[0].arn
  launch_type     = "FARGATE"
  desired_count   = 1

  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  dynamic "service_registries" {
    for_each = var.register_service_discovery ? [1] : []

    content {
      registry_arn = aws_service_discovery_service.this[0].arn
    }
  }

  dynamic "load_balancer" {
    for_each = var.alb_target_group_arn != null ? [1] : []

    content {
      target_group_arn = var.alb_target_group_arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200
  wait_for_steady_state              = false
  propagate_tags                     = "SERVICE"

  tags = merge(local.tags, { Name = "${var.name}-service" })
}
