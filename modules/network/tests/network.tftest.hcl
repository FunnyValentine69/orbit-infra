# This module declares no aws_nat_gateway resource block at all (see
# ADR 0002 / README no-NAT invariant); that is verified structurally by
# the no-NAT-gateway grep step in scripts/gates.sh, since terraform test
# cannot assert against a resource type absent from the configuration.

mock_provider "aws" {}

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
