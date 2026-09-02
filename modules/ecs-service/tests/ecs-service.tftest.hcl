mock_provider "aws" {
  override_resource {
    target = aws_iam_role.execution
    values = {
      arn = "arn:aws:iam::000000000000:role/orbit-test-api-exec"
    }
  }

  override_resource {
    target = aws_iam_role.task
    values = {
      arn = "arn:aws:iam::000000000000:role/orbit-test-api-task"
    }
  }
}

variables {
  name               = "orbit-test-api"
  env_id             = "test"
  cluster_arn        = "arn:aws:ecs:us-east-1:000000000000:cluster/orbit-test"
  image              = "example/placeholder@sha256:0000000000000000000000000000000000000000000000000000000000000"
  container_port     = 8000
  subnet_ids         = ["subnet-aaaaaaaa"]
  security_group_ids = ["sg-aaaaaaaa"]
}

run "env_id_invalid_rejected" {
  command = plan

  variables {
    env_id = "this-env-id-is-too-long"
  }

  expect_failures = [var.env_id]
}

run "disabled_yields_zero_resources" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_ecs_service.this) == 0
    error_message = "enabled=false must yield zero ECS services"
  }

  assert {
    condition     = length(aws_ecs_task_definition.this) == 0
    error_message = "enabled=false must yield zero task definitions"
  }

  assert {
    condition     = length(aws_iam_role.execution) == 0 && length(aws_iam_role.task) == 0
    error_message = "enabled=false must yield zero IAM roles"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 0
    error_message = "enabled=false must yield zero log groups"
  }
}

run "default_topology" {
  command = apply

  assert {
    condition     = aws_ecs_task_definition.this[0].runtime_platform[0].cpu_architecture == "ARM64"
    error_message = "task definition must run on ARM64"
  }

  assert {
    condition     = aws_ecs_task_definition.this[0].runtime_platform[0].operating_system_family == "LINUX"
    error_message = "task definition must run on LINUX"
  }

  assert {
    condition     = !can(jsondecode(aws_ecs_task_definition.this[0].container_definitions)[0].command)
    error_message = "container command must be absent when var.command is null"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["env_id"] == "test"
    error_message = "log group must carry the env_id tag"
  }

  assert {
    condition     = aws_iam_role.task[0].tags["env_id"] == "test"
    error_message = "task role must carry the env_id tag"
  }

  assert {
    condition     = length(aws_iam_role_policy.task_exec_command) == 1
    error_message = "execute-command policy must exist when enable_execute_command = true (the default)"
  }
}

run "command_set" {
  command = plan

  variables {
    command = ["python", "worker.py"]
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this[0].container_definitions)[0].command[0] == "python"
    error_message = "container command must be present when var.command is set"
  }
}

run "execute_command_disabled" {
  command = plan

  variables {
    enable_execute_command = false
  }

  assert {
    condition     = length(aws_iam_role_policy.task_exec_command) == 0
    error_message = "execute-command policy must be absent when enable_execute_command = false"
  }
}

run "alb_target_group_attached" {
  command = plan

  variables {
    alb_target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:000000000000:targetgroup/orbit-test-api/0000000000000000"
  }

  assert {
    condition     = length(aws_ecs_service.this[0].load_balancer) == 1
    error_message = "alb_target_group_arn set must yield exactly one load_balancer block"
  }

  assert {
    condition     = one(aws_ecs_service.this[0].load_balancer).container_name == var.name
    error_message = "load_balancer container_name must equal the service name"
  }

  assert {
    condition     = one(aws_ecs_service.this[0].load_balancer).target_group_arn == "arn:aws:elasticloadbalancing:us-east-1:000000000000:targetgroup/orbit-test-api/0000000000000000"
    error_message = "load_balancer target_group_arn must equal the input alb_target_group_arn"
  }
}

run "service_discovery_registered" {
  command = plan

  variables {
    register_service_discovery = true
    cloud_map_namespace_id     = "ns-aaaaaaaaaaaaaaaa"
  }

  assert {
    condition     = length(aws_service_discovery_service.this) == 1
    error_message = "register_service_discovery = true must yield exactly one Cloud Map service"
  }
}
