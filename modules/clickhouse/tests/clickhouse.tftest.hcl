# modules/ecs-service (upstream, not modifiable here) only exposes ARNs/
# names as outputs, not container_definitions contents — so these mock
# tests assert what's reachable via outputs (enabled/disabled signal,
# this module's own port/dns outputs). The actual container command,
# port mapping, env vars, and health check are verified against the real
# ECS task definition during the LocalStack apply gate.
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
  env_id              = "test"
  cluster_arn         = "arn:aws:ecs:us-east-1:000000000000:cluster/orbit-test"
  subnet_ids          = ["subnet-aaaaaaaa"]
  security_group_ids  = ["sg-aaaaaaaa"]
  password_secret_arn = "arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-test-clickhouse-password"
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
    condition     = output.port == 8123
    error_message = "port output must be 8123"
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
