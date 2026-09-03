# This module declares no aws_nat_gateway resource block at all (see
# ADR 0002 / README no-NAT invariant); that is verified structurally by
# the no-NAT-gateway grep step in scripts/gates.sh, since terraform test
# cannot assert against a resource type absent from the configuration.

mock_provider "aws" {
  override_resource {
    target = aws_vpc_endpoint.s3
    values = {
      prefix_list_id = "pl-mock12345"
    }
  }
}

variables {
  name   = "orbit-test"
  env_id = "test"
  cidr   = "10.42.0.0/16"
  azs    = ["us-east-1a", "us-east-1b"]
}

run "default_topology" {
  command = apply

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "expected exactly 2 public subnets"
  }

  assert {
    condition     = aws_subnet.public[0].availability_zone != aws_subnet.public[1].availability_zone
    error_message = "public subnets must be in distinct AZs"
  }

  assert {
    condition     = aws_subnet.private.availability_zone == "us-east-1a"
    error_message = "private subnet must be in the first AZ"
  }

  assert {
    condition     = length([for r in aws_route_table.private.route : r]) == 0
    error_message = "private route table must have no routes (no NAT, no default route)"
  }

  assert {
    condition     = aws_subnet.public[0].tags["env_id"] == "test" && aws_subnet.public[1].tags["env_id"] == "test" && aws_subnet.private.tags["env_id"] == "test"
    error_message = "every subnet must carry the env_id tag"
  }

  assert {
    condition     = output.s3_prefix_list_id != null && output.s3_prefix_list_id != ""
    error_message = "s3_prefix_list_id output must be non-null so callers can reference it in egress rules"
  }
}

run "env_id_invalid_rejected" {
  command = plan

  variables {
    env_id = "this-env-id-is-too-long"
  }

  expect_failures = [var.env_id]
}

run "azs_one_element_rejected" {
  command = plan

  variables {
    azs = ["us-east-1a"]
  }

  expect_failures = [var.azs]
}

run "azs_three_elements_rejected" {
  command = plan

  variables {
    azs = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  expect_failures = [var.azs]
}

run "azs_duplicate_rejected" {
  command = plan

  variables {
    azs = ["us-east-1a", "us-east-1a"]
  }

  expect_failures = [var.azs]
}

run "interface_endpoints_disabled" {
  command = plan

  variables {
    enable_interface_endpoints = false
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0
    error_message = "enable_interface_endpoints=false must yield zero interface endpoints"
  }
}
