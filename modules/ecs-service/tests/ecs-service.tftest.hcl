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
