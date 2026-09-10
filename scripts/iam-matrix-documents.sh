#!/usr/bin/env bash

# Permission-policy documents covered by the IAM matrix. This file is sourced
# by both inventory extraction and simulator execution.
# shellcheck disable=SC2034  # sourced by iam-matrix-inventory.sh, iam-simulate.sh and iam-simulate-roles.sh
core_documents=(
  aws_iam_role_policy.plan_reader_deny
  aws_iam_role_policy.plan_reader_state
  aws_iam_policy.task_boundary
  aws_iam_policy.deployer_state
  aws_iam_policy.deployer_ec2
  aws_iam_policy.deployer_elb_ecs
  aws_iam_policy.deployer_data
  aws_iam_policy.deployer_iam
  aws_iam_policy.deployer_guard
  aws_iam_role_policy.publisher
)
