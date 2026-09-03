mock_provider "aws" {
  override_resource {
    target = module.service.aws_iam_role.execution
    values = {
      arn = "arn:aws:iam::000000000000:role/orbit-test-clickhouse-exec"
    }
  }

  override_resource {
    target = module.service.aws_iam_role.task
    values = {
      arn = "arn:aws:iam::000000000000:role/orbit-test-clickhouse-task"
    }
  }
}

variables {
  region              = "us-east-1"
  env_id              = "test"
  cluster_arn         = "arn:aws:ecs:us-east-1:000000000000:cluster/orbit-test"
  subnet_ids          = ["subnet-aaaaaaaa"]
  security_group_ids  = ["sg-aaaaaaaa"]
  password_secret_arn = "arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-test-clickhouse-password"
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
    condition     = output.service_name == null
    error_message = "enabled=false must yield a null service_name (zero ECS resources created)"
  }
}

run "default_topology" {
  command = apply

  assert {
    condition     = output.service_name != null
    error_message = "enabled=true (default) must create the service"
  }

  assert {
    condition     = jsondecode(output.container_definitions_json)[0].portMappings[0].containerPort == 8123
    error_message = "container port mapping must be 8123"
  }

  assert {
    condition     = contains([for s in jsondecode(output.container_definitions_json)[0].secrets : s.name], "CLICKHOUSE_PASSWORD")
    error_message = "secrets must contain a CLICKHOUSE_PASSWORD entry"
  }

  assert {
    condition     = contains([for e in jsondecode(output.container_definitions_json)[0].environment : e.name], "CLICKHOUSE_DB") && contains([for e in jsondecode(output.container_definitions_json)[0].environment : e.name], "CLICKHOUSE_USER")
    error_message = "environment must contain CLICKHOUSE_DB and CLICKHOUSE_USER"
  }
}

run "discovery_dns_name_computed" {
  command = plan

  variables {
    namespace_name = "dev.orbit.internal"
  }

  assert {
    condition     = output.discovery_dns_name == "clickhouse.dev.orbit.internal"
    error_message = "discovery_dns_name must be name.namespace_name"
  }
}
