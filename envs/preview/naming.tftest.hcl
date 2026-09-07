mock_provider "aws" {
  override_data {
    target = module.network.data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "000000000000"
      arn        = "arn:aws:iam::000000000000:user/mock"
      user_id    = "AIDAMOCK"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
}

variables {
  target        = "localstack"
  env_id        = "xxxxxxxxxc"
  operator_cidr = "203.0.113.7/32"
}

run "name_charset_rejected" {
  command = plan

  variables {
    name = "-invalid"
  }

  expect_failures = [var.name]
}

run "first_collision_pair_shorter_env" {
  command = plan

  variables {
    name   = "aaaaaaaaaaaaaaa-bc"
    env_id = "xxxxxxxxxc"
  }

  assert {
    condition     = local.lb_name == "aaaaaaaaaaaaaaa-xxxxxxxxxc-alb"
    error_message = "the shorter first-pair LB name must preserve its complete env_id segment"
  }

  assert {
    condition     = local.tg_name == "aaaaaaaaaaaaaaa-xxxxxxxxxc-tg"
    error_message = "the shorter first-pair target-group name must preserve its complete env_id segment"
  }
}

run "first_collision_pair_longer_env" {
  command = plan

  variables {
    name   = "aaaaaaaaaaaaaaa-bc"
    env_id = "b-xxxxxxxxxc"
  }

  assert {
    condition     = local.lb_name == "aaaaaaaaaaaaaaa-b-xxxxxxxxxc-alb"
    error_message = "the longer first-pair LB name must differ in its complete env_id segment"
  }

  assert {
    condition     = local.tg_name == "aaaaaaaaaaaaaaa-b-xxxxxxxxxc-tg"
    error_message = "the longer first-pair target-group name must differ in its complete env_id segment"
  }
}

run "second_collision_pair_shorter_env" {
  command = plan

  variables {
    name   = "aaaaaaaaaaaaaaaa-b"
    env_id = "xxxxxxxxxc"
  }

  assert {
    condition     = local.lb_name == "aaaaaaaaaaaaaaa-xxxxxxxxxc-alb"
    error_message = "the shorter second-pair LB name must preserve its complete env_id segment"
  }

  assert {
    condition     = local.tg_name == "aaaaaaaaaaaaaaaa-xxxxxxxxxc-tg"
    error_message = "the shorter second-pair target-group name must preserve its complete env_id segment"
  }
}

run "second_collision_pair_longer_env" {
  command = plan

  variables {
    name   = "aaaaaaaaaaaaaaaa-b"
    env_id = "b-xxxxxxxxxc"
  }

  assert {
    condition     = local.lb_name == "aaaaaaaaaaaaaaa-b-xxxxxxxxxc-alb"
    error_message = "the longer second-pair LB name must differ in its complete env_id segment"
  }

  assert {
    condition     = local.tg_name == "aaaaaaaaaaaaaaaa-b-xxxxxxxxxc-tg"
    error_message = "the longer second-pair target-group name must differ in its complete env_id segment"
  }
}

run "default_name_eight_character_env" {
  command = plan

  variables {
    env_id = "abcdefgh"
  }

  assert {
    condition     = length(local.lb_name) == 28 && length(local.tg_name) == 28
    error_message = "the default name with an eight-character env_id must produce 28-character LB and target-group names"
  }
}

run "default_name_twelve_character_env" {
  command = plan

  variables {
    env_id = "abcdefghijkl"
  }

  assert {
    condition     = length(local.lb_name) == 32 && length(local.tg_name) == 32
    error_message = "the default name with a twelve-character env_id must produce 32-character LB and target-group names"
  }
}
