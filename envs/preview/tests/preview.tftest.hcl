# No NAT gateway resource block exists anywhere in this composition or its
# modules (ADR 0002 no-NAT invariant); terraform test cannot assert against
# a resource type absent from the configuration, so that invariant is
# checked structurally by the no-nat-gateway grep step in scripts/gates.sh.
mock_provider "aws" {
  override_data {
    target = module.network.data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }
}

variables {
  env_id        = "valid-env"
  operator_cidr = "203.0.113.7/32"
}

run "operator_cidr_open_to_world_rejected" {
  command = plan

  variables {
    operator_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.operator_cidr]
}

run "env_id_too_long_rejected" {
  command = plan

  variables {
    env_id = "this-env-id-is-too-long"
  }

  expect_failures = [var.env_id]
}

run "valid_plan" {
  command = plan

  assert {
    condition     = length(aws_security_group.alb.ingress) == 1
    error_message = "ALB security group must have exactly one ingress rule"
  }

  assert {
    condition     = length(one(aws_security_group.alb.ingress).cidr_blocks) == 1 && contains(one(aws_security_group.alb.ingress).cidr_blocks, "203.0.113.7/32")
    error_message = "ALB ingress cidr_blocks must equal [operator_cidr]"
  }

  assert {
    condition     = one(aws_security_group.alb.ingress).from_port == 80 && one(aws_security_group.alb.ingress).to_port == 80
    error_message = "ALB ingress must be on port 80"
  }
}
