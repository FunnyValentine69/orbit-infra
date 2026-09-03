# --- Deterministic ARN locals (PR#2 Tier 3: plan-time-known policy
# documents) ---
#
# Every data.aws_iam_policy_document below must resolve to a fully known
# string on a fresh state so bootstrap/policy-size-check.sh can measure it
# before any apply. References to created-resource attributes (bucket arn,
# repo arn, policy arn, role arn) are replaced with strings built from
# these data sources plus the deterministic names each resource is given
# elsewhere in bootstrap/*.tf.
data "aws_partition" "current" {}

locals {
  # Matches aws_s3_bucket.state (state.tf: bucket = "${var.name}-tfstate").
  state_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.name}-tfstate"

  # Matches aws_ecr_repository.repos' for_each set (ecr.tf). Must stay in
  # sync with that toset() if repos are added/removed there.
  ecr_repo_names = toset([
    "placeholder",
    "orbit-api",
    "orbit-worker",
    "orbit-clickhouse",
    "mirror/clickhouse",
    "mirror/redis",
  ])
  ecr_repo_arns = [
    for r in local.ecr_repo_names :
    "arn:${data.aws_partition.current.partition}:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.name}/${r}"
  ]

  # Matches aws_iam_policy.task_boundary (name = "${var.name}-task-boundary").
  task_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name}-task-boundary"

  # Matches aws_iam_role.{plan_reader,deployer,publisher} names below.
  plan_reader_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-plan-reader"
  deployer_role_arn    = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-deployer"
  publisher_role_arn   = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-publisher"

  # Matches aws_kms_alias.signing (kms.tf: name = "alias/${var.name}-signing").
  # The KMS key's own ARN is not deterministic (contains a generated key
  # id), so the publisher's signing grant below is instead scoped to
  # arn:<partition>:kms:<region>:<account>:key/* and narrowed with the
  # kms:ResourceAliases condition key, which AWS documents as a supported
  # condition key on KMS key resources
  # (docs.aws.amazon.com/kms/latest/developerguide/policy-conditions.html).
  kms_signing_alias = "alias/${var.name}-signing"
}

# --- Trust policies (WebIdentity from the GitHub OIDC provider) ---

data "aws_iam_policy_document" "plan_reader_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "deployer_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "publisher_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main",
      ]
    }
  }
}

# --- Roles ---

resource "aws_iam_role" "plan_reader" {
  name               = "${var.name}-plan-reader"
  assume_role_policy = data.aws_iam_policy_document.plan_reader_trust.json

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "deployer" {
  name               = "${var.name}-deployer"
  assume_role_policy = data.aws_iam_policy_document.deployer_trust.json

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "publisher" {
  name               = "${var.name}-publisher"
  assume_role_policy = data.aws_iam_policy_document.publisher_trust.json

  lifecycle {
    prevent_destroy = true
  }
}

# --- plan-reader permissions ---

resource "aws_iam_role_policy_attachment" "plan_reader_readonly" {
  role       = aws_iam_role.plan_reader.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"

  lifecycle {
    prevent_destroy = true
  }
}

# ReadOnlyAccess grants s3:Get* on *; PR-triggered code must not read
# arbitrary buckets or secrets.
data "aws_iam_policy_document" "plan_reader_deny" {
  statement {
    sid     = "DenyReadStateObjectsOutsideScope"
    effect  = "Deny"
    actions = ["s3:GetObject", "s3:GetObjectVersion"]
    not_resources = [
      "${local.state_bucket_arn}/envs/preview/*",
      "${local.state_bucket_arn}/bootstrap/*",
    ]
  }

  statement {
    sid           = "DenyListBucketOutsideScope"
    effect        = "Deny"
    actions       = ["s3:ListBucket"]
    not_resources = [local.state_bucket_arn]
  }

  # ReadOnlyAccess's broad s3:ListBucket would otherwise let plan-reader
  # enumerate every prefix in the state bucket (leases/*, other envs).
  # Deny listing the state bucket unless scoped to the allowed prefixes,
  # and deny it outright when no prefix condition is present at all.
  statement {
    sid       = "DenyListBucketOutsideScopePrefix"
    effect    = "Deny"
    actions   = ["s3:ListBucket", "s3:ListBucketVersions"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringNotLike"
      variable = "s3:prefix"
      values   = ["envs/preview/*", "bootstrap/*", "envs/preview", "bootstrap"]
    }
  }

  statement {
    sid       = "DenyListBucketMissingPrefix"
    effect    = "Deny"
    actions   = ["s3:ListBucket", "s3:ListBucketVersions"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "Null"
      variable = "s3:prefix"
      values   = ["true"]
    }
  }

  statement {
    sid    = "DenySecretsAndParams"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:GetParameterHistory",
      "kms:Decrypt",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetLayerVersion",
      "lambda:GetLayerVersionByArn",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "plan_reader_deny" {
  name   = "${var.name}-plan-reader-deny"
  role   = aws_iam_role.plan_reader.id
  policy = data.aws_iam_policy_document.plan_reader_deny.json

  lifecycle {
    prevent_destroy = true
  }
}

# plan-reader may list/read only the preview env state and the bootstrap
# state itself; no write actions anywhere.
data "aws_iam_policy_document" "plan_reader_state" {
  statement {
    sid       = "ListStatePrefixes"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["envs/preview/*", "bootstrap/*"]
    }
  }

  statement {
    sid     = "ReadStateObjects"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${local.state_bucket_arn}/envs/preview/*",
      "${local.state_bucket_arn}/bootstrap/*",
    ]
  }
}

resource "aws_iam_role_policy" "plan_reader_state" {
  name   = "${var.name}-plan-reader-state"
  role   = aws_iam_role.plan_reader.id
  policy = data.aws_iam_policy_document.plan_reader_state.json

  lifecycle {
    prevent_destroy = true
  }
}

# --- task permissions boundary (PR #2 Tier 2 / R3, A1) ---
#
# Maximum permission set an ECS execution or task role created by the
# deployer may ever hold, per modules/ecs-service/main.tf (execution_managed,
# execution_secrets, task_exec_command) and envs/preview/main.tf
# (local.api_bucket_policy_json). This is a superset of every grant those
# resources make so attaching it never removes functionality; see ADR 0005
# Amendment 2026-09-02 for the naming contract (${var.name}-task-boundary).
data "aws_iam_policy_document" "task_boundary" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPull"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = local.ecr_repo_arns
  }

  statement {
    sid       = "LogStreams"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/orbit/*"]
  }

  statement {
    sid       = "ProjectSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.name}-*"]
  }

  statement {
    sid    = "EcsExec"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ProjectDataBucket"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${var.name}-*",
      "arn:aws:s3:::${var.name}-*/*",
    ]
  }
}

resource "aws_iam_policy" "task_boundary" {
  name   = "${var.name}-task-boundary"
  policy = data.aws_iam_policy_document.task_boundary.json

  lifecycle {
    prevent_destroy = true
  }
}

# --- deployer permissions ---

# F3: deployer permissions, split into customer-managed policies
# (aws_iam_policy_document.deployer_<group> below) so each attached
# managed-policy document stays under the AWS 6,144 non-whitespace-
# character quota; the prior single inline aws_iam_role_policy
# (~13,966 stripped chars) exceeded the 10,240 inline-aggregate quota.
# Grouped by service per PR#2 Tier 2b review F3; bootstrap/
# policy-size-check.sh enforces both quotas in CI via `scripts/gates.sh
# policy-size`. Statement content/conditions are unchanged from the
# prior single deployer document except where F1/F4/F5/F6 edited them.

data "aws_iam_policy_document" "deployer_state" {
  # (a) preview env terraform state + apply leases: read/write/list.
  statement {
    sid     = "StateAndLeaseObjects"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = [
      "${local.state_bucket_arn}/envs/preview/*",
      "${local.state_bucket_arn}/leases/*",
    ]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucketVersions", "s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["envs/preview/*", "leases/*"]
    }
  }
}



resource "aws_iam_policy" "deployer_state" {
  name   = "${var.name}-deployer-state"
  policy = data.aws_iam_policy_document.deployer_state.json

  lifecycle {
    prevent_destroy = true
  }
}


data "aws_iam_policy_document" "deployer_ec2" {
  # --- (b) EC2 networking. Every action below IS resource-scoped per the
  # verified condition-key table (iam-condition-keys.md, EC2 section);
  # `resources = ["*"]` is kept (the ARN is unknown before create, and
  # Terraform's IAM engine still enforces the conditions below against
  # any resource matched by "*"), scoped instead by tag conditions.
  # Only the 7 Describe* actions the table confirms `* only` (plus two
  # untested-but-consistent Describe* calls, flagged) are left bare.
  statement {
    #checkov:skip=CKV_AWS_111:table-confirmed * only EC2 Describe* actions; no condition key exists (iam-condition-keys.md EC2 section)
    #checkov:skip=CKV_AWS_356:same as above
    sid    = "Ec2DescribeStarOnly"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeRegions",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute", # not one of the table's 7 tested Describe* rows; treated consistently, flagged
      "ec2:DescribeSubnets",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeRouteTables",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules", # not one of the table's 7 tested Describe* rows; treated consistently, flagged
      "ec2:DescribeTags",
      "ec2:DescribeNetworkInterfaces", # F6: ENI discovery only for SG-delete-path lookups; no ENI deletion granted
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Ec2CreateWithTag"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc",
      "ec2:CreateSubnet",
      "ec2:CreateSecurityGroup",
      "ec2:CreateRouteTable",
      "ec2:CreateInternetGateway",
      "ec2:CreateVpcEndpoint",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  # ec2:CreateTags is the dependent action the table shows carries
  # `ec2:CreateAction` on all 106 of its resource-type rows; scoped here
  # to only the create actions above (iam-condition-keys.md EC2 notes).
  statement {
    sid    = "Ec2CreateTagsForCreateActions"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values = [
        "CreateVpc",
        "CreateSubnet",
        "CreateSecurityGroup",
        "CreateRouteTable",
        "CreateInternetGateway",
        "CreateVpcEndpoint",
        "AuthorizeSecurityGroupIngress",
        "AuthorizeSecurityGroupEgress",
      ]
    }
  }

  # F4: AuthorizeSecurityGroupIngress/Egress create the security-group-rule
  # resource and support tag-on-create per the table, but ONLY the two
  # separate-resource rules (aws_vpc_security_group_ingress_rule/
  # egress_rule in envs/preview/main.tf, which set `tags =`) exercise
  # this path; the request-tag condition never matches for those calls.
  # The RequestTag path stays scoped to the security-group-rule resource
  # type and is paired with the CreateAction values added to
  # Ec2CreateTagsForCreateActions above, per F4.
  statement {
    sid    = "Ec2SecurityGroupRuleCreateWithTag"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  # F4: AuthorizeSecurityGroupIngress/Egress and Revoke* are also allowed
  # here, scoped to the pre-existing security-group* resource's
  # ec2:ResourceTag (never aws:RequestTag), so the inline ingress/egress
  # blocks in modules/network/main.tf and envs/preview/main.tf (which
  # issue Authorize/Revoke calls with no tags on the call itself) keep
  # working. ec2:ReplaceRoute/ReplaceRouteTableAssociation/
  # ModifySecurityGroupRules are not covered by iam-condition-keys.md (no
  # verified condition key), but are conditioned here on the same
  # ec2:ResourceTag/Project pattern as their sibling route-table*/
  # security-group* actions per F1 direction, not table backing.
  statement {
    sid    = "Ec2ModifyDeleteWithResourceTag"
    effect = "Allow"
    actions = [
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:DeleteVpcEndpoints",
      "ec2:ModifyVpcEndpoint",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid    = "Ec2DeleteTags"
    effect = "Allow"
    actions = [
      "ec2:DeleteTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # T3: post-create tag updates (e.g. re-tagging an already-created
  # resource, not tagging at create time), scoped by ec2:ResourceTag
  # instead of the ec2:CreateAction condition on Ec2CreateTagsForCreateActions.
  statement {
    sid    = "Ec2CreateTagsForResourceTag"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }
}



resource "aws_iam_policy" "deployer_ec2" {
  name   = "${var.name}-deployer-ec2"
  policy = data.aws_iam_policy_document.deployer_ec2.json

  lifecycle {
    prevent_destroy = true
  }
}


data "aws_iam_policy_document" "deployer_elb_ecs" {
  # --- (c) ALB + target group + listener. ---
  statement {
    #checkov:skip=CKV_AWS_111:table-confirmed * only ELBv2 Describe* actions, zero condition keys (iam-condition-keys.md ELBv2 section)
    #checkov:skip=CKV_AWS_356:same as above
    sid    = "ElbDescribeStarOnly"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeListenerAttributes", # A3: provider 6.62.0 read
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ElbCreateWithTag"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  # F1: RegisterTargets/DeregisterTargets are not covered by
  # iam-condition-keys.md (no verified condition key), but are
  # conditioned here on the same elasticloadbalancing:ResourceTag/Project
  # pattern as their sibling targetgroup* actions per F1 direction, not
  # table backing.
  statement {
    sid    = "ElbModifyDeleteWithResourceTag"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # AddTags carries elasticloadbalancing:CreateAction on all 10 of its
  # resource-type rows (iam-condition-keys.md ELBv2 notes).
  statement {
    sid       = "ElbAddTags"
    effect    = "Allow"
    actions   = ["elasticloadbalancing:AddTags"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }

    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:CreateAction"
      values = [
        "CreateLoadBalancer",
        "CreateTargetGroup",
        "CreateListener",
      ]
    }
  }

  statement {
    sid       = "ElbRemoveTags"
    effect    = "Allow"
    actions   = ["elasticloadbalancing:RemoveTags"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # T3: post-create tag updates, scoped by ResourceTag instead of the
  # CreateAction condition on ElbAddTags.
  statement {
    sid       = "ElbAddTagsForResourceTag"
    effect    = "Allow"
    actions   = ["elasticloadbalancing:AddTags"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # DescribeTargetHealth is not covered by iam-condition-keys.md; no
  # verified condition key, kept unconditioned (read-only, consistent
  # with the ELBv2 Describe* pattern).
  statement {
    #checkov:skip=CKV_AWS_111:not covered by iam-condition-keys.md (ELBv2 section); no verified condition key exists
    #checkov:skip=CKV_AWS_356:same as above
    sid       = "ElbDescribeTargetHealth"
    effect    = "Allow"
    actions   = ["elasticloadbalancing:DescribeTargetHealth"]
    resources = ["*"]
  }

  # --- (d) ECS cluster/service/task definitions. ---
  statement {
    #checkov:skip=CKV_AWS_111:table-confirmed * only ECS actions (iam-condition-keys.md ECS section: DeregisterTaskDefinition, DescribeTaskDefinition)
    #checkov:skip=CKV_AWS_356:same as above
    sid    = "EcsStarOnly"
    effect = "Allow"
    actions = [
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcsCreateWithTag"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:CreateService",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid    = "EcsModifyDeleteDescribeWithResourceTag"
    effect = "Allow"
    actions = [
      "ecs:DeleteCluster",
      "ecs:DescribeClusters",
      "ecs:UpdateService",
      "ecs:DeleteService",
      "ecs:DescribeServices",
      "ecs:DeleteTaskDefinitions",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ecs:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # ecs:TagResource carries ecs:CreateAction on all 9 of its resource-type
  # rows (iam-condition-keys.md ECS notes).
  statement {
    sid       = "EcsTagResource"
    effect    = "Allow"
    actions   = ["ecs:TagResource"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }

    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values = [
        "CreateCluster",
        "CreateService",
        "RegisterTaskDefinition",
      ]
    }
  }

  statement {
    sid    = "EcsUntagAndListTags"
    effect = "Allow"
    actions = [
      "ecs:UntagResource",
      "ecs:ListTagsForResource",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ecs:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # ListServices/ListTaskDefinitions are not covered by
  # iam-condition-keys.md; no verified condition key, kept unconditioned.
  statement {
    #checkov:skip=CKV_AWS_111:not covered by iam-condition-keys.md (ECS section); no verified condition key exists
    #checkov:skip=CKV_AWS_356:same as above
    sid    = "EcsUntabledActions"
    effect = "Allow"
    actions = [
      "ecs:ListServices",
      "ecs:ListTaskDefinitions",
    ]
    resources = ["*"]
  }

  # --- (e) Cloud Map namespace + service. ---
  # ListTagsForResource is table-confirmed * only with zero condition
  # keys; ListNamespaces/ListServices are not covered by the table.
  statement {
    #checkov:skip=CKV_AWS_111:table-confirmed * only (ListTagsForResource) or uncovered (ListNamespaces/ListServices) Cloud Map actions (iam-condition-keys.md Cloud Map section)
    #checkov:skip=CKV_AWS_356:same as above
    sid    = "ServiceDiscoveryStarOnlyNoCondition"
    effect = "Allow"
    actions = [
      "servicediscovery:ListTagsForResource",
      "servicediscovery:ListNamespaces",
      "servicediscovery:ListServices",
      # T2: GetOperation polls an operation ID, which is not taggable, so
      # it cannot carry the aws:ResourceTag/Project condition the other
      # actions below use; kept unconditioned here instead.
      "servicediscovery:GetOperation",
    ]
    resources = ["*"]
  }

  # CreatePrivateDnsNamespace is table-confirmed * only but supports
  # tag-on-create via aws:RequestTag (R1: stays Resource = "*").
  statement {
    sid       = "ServiceDiscoveryCreateNamespaceWithTag"
    effect    = "Allow"
    actions   = ["servicediscovery:CreatePrivateDnsNamespace"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid       = "ServiceDiscoveryCreateServiceWithTag"
    effect    = "Allow"
    actions   = ["servicediscovery:CreateService"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  # Cloud Map has no service-specific ResourceTag key (R1); the generic
  # aws:ResourceTag/Project applies.
  statement {
    sid    = "ServiceDiscoveryReadDeleteUpdateWithResourceTag"
    effect = "Allow"
    actions = [
      "servicediscovery:DeleteNamespace",
      "servicediscovery:GetNamespace",
      "servicediscovery:DeleteService",
      "servicediscovery:GetService",
      "servicediscovery:UpdateService",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid       = "ServiceDiscoveryTagResource"
    effect    = "Allow"
    actions   = ["servicediscovery:TagResource"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  # UntagResource: the table shows no aws:ResourceTag/aws:RequestTag
  # scoping key documented for this action; kept unconditioned.
  statement {
    #checkov:skip=CKV_AWS_111:table-confirmed no ResourceTag/RequestTag condition key for servicediscovery:UntagResource (iam-condition-keys.md Cloud Map section)
    #checkov:skip=CKV_AWS_356:same as above
    sid       = "ServiceDiscoveryUntagResource"
    effect    = "Allow"
    actions   = ["servicediscovery:UntagResource"]
    resources = ["*"]
  }

  # Private DNS namespace create/delete provisions a Route 53 hosted zone
  # under the hood (cloud-map-api-permissions-ref.html); CreateHostedZone
  # and ListHostedZonesByName accept no resource-level ARN and stay on "*".
  statement {
    #checkov:skip=CKV_AWS_111:route53:CreateHostedZone/ListHostedZonesByName accept no resource ARN (cloud-map-api-permissions-ref.html)
    #checkov:skip=CKV_AWS_356:same as above
    sid    = "Route53HostedZoneStarOnly"
    effect = "Allow"
    actions = [
      "route53:CreateHostedZone",
      "route53:ListHostedZonesByName",
    ]
    resources = ["*"]
  }

  # DeleteNamespace deletes the backing hosted zone; scope to the
  # hosted-zone resource type.
  statement {
    #checkov:skip=CKV_AWS_111:no documented ResourceTag/RequestTag condition key for these route53 hosted-zone actions
    #checkov:skip=CKV_AWS_356:same as above
    # CreatePrivateDnsNamespace needs GetHostedZone on the zone Cloud Map
    # creates; DeleteNamespace needs no Route 53 action (Cloud Map reference),
    # so no hosted-zone delete or tag rights are granted.
    sid       = "Route53HostedZoneRead"
    effect    = "Allow"
    actions   = ["route53:GetHostedZone"]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }
}



resource "aws_iam_policy" "deployer_elb_ecs" {
  name   = "${var.name}-deployer-elb-ecs"
  policy = data.aws_iam_policy_document.deployer_elb_ecs.json

  lifecycle {
    prevent_destroy = true
  }
}


data "aws_iam_policy_document" "deployer_data" {
  # --- (f) CloudWatch log groups, /orbit/<env_id>/<name>. ---
  statement {
    #checkov:skip=CKV_AWS_111:table-confirmed * only (DescribeLogGroups) (iam-condition-keys.md CloudWatch Logs section, A3)
    #checkov:skip=CKV_AWS_356:same as above
    sid       = "LogsDescribeStarOnly"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid    = "LogsCreateWithTag"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:TagResource",
    ]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/orbit/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid    = "LogsModifyDeleteWithResourceTag"
    effect = "Allow"
    actions = [
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:UntagResource",
      "logs:ListTagsForResource",
    ]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/orbit/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # --- (g) the ClickHouse password secret. ---
  statement {
    sid    = "ClickhouseSecretCreateWithTag"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:TagResource",
    ]
    resources = ["arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.name}-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid    = "ClickhouseSecretReadModifyWithResourceTag"
    effect = "Allow"
    actions = [
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:GetSecretValue",
      "secretsmanager:UntagResource",
      "secretsmanager:GetResourcePolicy",
    ]
    resources = ["arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.name}-*"]

    # F5: Secrets Manager has no service-specific ResourceTag condition
    # key (iam-condition-keys.md Secrets Manager section documents only
    # the literal string "tag-key", an unresolved AWS-docs template
    # artifact, not a real condition key); the generic aws:ResourceTag
    # key, also documented present on this row, is used instead.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # --- Phase 3: SNS topics + subscriptions, project-scoped. ---
  statement {
    sid    = "SnsCreateWithTag"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:TagResource",
    ]
    resources = ["arn:aws:sns:${var.region}:${data.aws_caller_identity.current.account_id}:${var.name}-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid    = "SnsRestWithResourceTag"
    effect = "Allow"
    actions = [
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:ListTagsForResource",
      "sns:UntagResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
    ]
    resources = ["arn:aws:sns:${var.region}:${data.aws_caller_identity.current.account_id}:${var.name}-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # --- Phase 3: CloudWatch alarms, project-scoped. ---
  statement {
    sid    = "CloudwatchAlarmCreateWithTag"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:TagResource",
    ]
    resources = ["arn:aws:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:${var.name}-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid    = "CloudwatchAlarmRestWithResourceTag"
    effect = "Allow"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:UntagResource",
    ]
    resources = ["arn:aws:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:${var.name}-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_tag]
    }
  }

  # --- (h) tag-based resource discovery; tag:GetResources has no
  # resource-level scoping, not covered by iam-condition-keys.md. ---
  statement {
    #checkov:skip=CKV_AWS_111:tag:GetResources documents no resource-level scoping; not covered by iam-condition-keys.md
    #checkov:skip=CKV_AWS_356:same as above
    sid       = "TagDiscovery"
    effect    = "Allow"
    actions   = ["tag:GetResources"]
    resources = ["*"]
  }

  # --- A3: provider 6.62.0 read additions, project data bucket. ---
  statement {
    #checkov:skip=CKV_AWS_111:read-only bucket describe actions; scoped to the project bucket name pattern via Resource, not a tag condition (A3)
    #checkov:skip=CKV_AWS_356:same as above
    sid    = "S3BucketDescribeReads"
    effect = "Allow"
    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketWebsite",
      "s3:GetBucketLogging",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketPolicy",
      "s3:GetBucketPolicyStatus",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetAccelerateConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = ["arn:aws:s3:::${var.name}-*"]
  }

  # (j) the preview data bucket (envs/preview aws_s3_bucket.data, named
  # "<name>-<env_id>-data") plus its public-access-block and object
  # lifecycle. Scoped to bucket ARNs containing the project name (see (i)
  # for why a single env_id can't be baked in here).
  statement {
    sid    = "EnvDataBucketLifecycle"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      # T4: force_destroy on the data bucket needs to abort/enumerate any
      # in-flight multipart uploads to complete.
      "s3:ListBucketMultipartUploads",
      "s3:AbortMultipartUpload",
    ]
    resources = [
      "arn:aws:s3:::${var.name}-*-data",
      "arn:aws:s3:::${var.name}-*-data/*",
    ]
  }
}



resource "aws_iam_policy" "deployer_data" {
  name   = "${var.name}-deployer-data"
  policy = data.aws_iam_policy_document.deployer_data.json

  lifecycle {
    prevent_destroy = true
  }
}


data "aws_iam_policy_document" "deployer_iam" {
  # --- (i) execution/task IAM roles for ECS services. ---
  # A1(ii): CreateRole must set the boundary to the exact task-boundary
  # policy ARN.
  statement {
    sid       = "EnvServiceRoleCreateWithBoundary"
    effect    = "Allow"
    actions   = ["iam:CreateRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*${var.name}*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.task_boundary_arn]
    }
  }

  # A1(ii)+(iv): AttachRolePolicy requires the boundary AND is limited to
  # the ECS execution managed policy (the module attaches no
  # customer-managed policy via AttachRolePolicy; task_custom is an
  # inline aws_iam_role_policy, not an attachment).
  statement {
    sid       = "EnvServiceRoleAttachPolicy"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*${var.name}*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.task_boundary_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
    }
  }

  statement {
    sid       = "EnvServiceRolePutPolicy"
    effect    = "Allow"
    actions   = ["iam:PutRolePolicy"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*${var.name}*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.task_boundary_arn]
    }
  }

  statement {
    sid       = "EnvServiceRolePermissionsBoundarySet"
    effect    = "Allow"
    actions   = ["iam:PutRolePermissionsBoundary"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*${var.name}*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.task_boundary_arn]
    }
  }

  # Actions not covered by A1's boundary requirement: no condition added.
  statement {
    sid    = "EnvServiceRoleLifecycle"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*${var.name}*"]
  }

  # A4: service-linked roles ELBv2 and ECS depend on, each pinned to its
  # exact service-linked-role ARN and gated by iam:AWSServiceName.
  statement {
    sid       = "IamServiceLinkedRoleElb"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "IamServiceLinkedRoleEcs"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com"]
    }
  }

  # A1(iii): explicit denies enforcing the boundary can never be stripped
  # or bypassed, regardless of which Allow statement above would
  # otherwise permit the call.
  statement {
    sid       = "DenyDeleteRolePermissionsBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyRoleMutationMissingBoundary"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
    ]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "iam:PermissionsBoundary"
      values   = ["true"]
    }
  }

  statement {
    sid    = "DenyRoleMutationWrongBoundary"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
    ]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.task_boundary_arn]
    }
  }

  # PassRole is kept as its own statement (not merged into the role
  # statements above) and restricted with iam:PassedToService so the
  # deployer can only hand these roles to ECS, never to itself or another
  # service (A1 vi).
  statement {
    sid       = "PassEnvRolesOnly"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*${var.name}*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}



resource "aws_iam_policy" "deployer_iam" {
  name   = "${var.name}-deployer-iam"
  policy = data.aws_iam_policy_document.deployer_iam.json

  lifecycle {
    prevent_destroy = true
  }
}


data "aws_iam_policy_document" "deployer_guard" {
  # Hard cap: see the historical rationale kept from the pre-PR#2 version
  # of this file — Deny always wins over Allow in IAM evaluation, so this
  # statement is the actual enforcement point keeping the deployer from
  # mutating or passing its own role, plan-reader, or publisher (A1 v:
  # kept unchanged).
  statement {
    sid    = "DenyMutatingOwnControlRoles"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
    ]
    resources = [
      local.deployer_role_arn,
      local.plan_reader_role_arn,
      local.publisher_role_arn,
    ]
  }
}



resource "aws_iam_policy" "deployer_guard" {
  name   = "${var.name}-deployer-guard"
  policy = data.aws_iam_policy_document.deployer_guard.json

  lifecycle {
    prevent_destroy = true
  }
}


resource "aws_iam_role_policy_attachment" "deployer_state" {
  role       = aws_iam_role.deployer.name
  policy_arn = aws_iam_policy.deployer_state.arn

  lifecycle {
    prevent_destroy = true
  }
}


resource "aws_iam_role_policy_attachment" "deployer_ec2" {
  role       = aws_iam_role.deployer.name
  policy_arn = aws_iam_policy.deployer_ec2.arn

  lifecycle {
    prevent_destroy = true
  }
}


resource "aws_iam_role_policy_attachment" "deployer_elb_ecs" {
  role       = aws_iam_role.deployer.name
  policy_arn = aws_iam_policy.deployer_elb_ecs.arn

  lifecycle {
    prevent_destroy = true
  }
}


resource "aws_iam_role_policy_attachment" "deployer_data" {
  role       = aws_iam_role.deployer.name
  policy_arn = aws_iam_policy.deployer_data.arn

  lifecycle {
    prevent_destroy = true
  }
}


resource "aws_iam_role_policy_attachment" "deployer_iam" {
  role       = aws_iam_role.deployer.name
  policy_arn = aws_iam_policy.deployer_iam.arn

  lifecycle {
    prevent_destroy = true
  }
}


resource "aws_iam_role_policy_attachment" "deployer_guard" {
  role       = aws_iam_role.deployer.name
  policy_arn = aws_iam_policy.deployer_guard.arn

  lifecycle {
    prevent_destroy = true
  }
}


# --- publisher permissions ---

data "aws_iam_policy_document" "publisher" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
    ]
    resources = local.ecr_repo_arns
  }

  statement {
    sid       = "SigningKey"
    effect    = "Allow"
    actions   = ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"]
    resources = ["arn:${data.aws_partition.current.partition}:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/*"]

    # kms:ResourceAliases is multivalued: AWS requires a ForAnyValue or
    # ForAllValues set operator (KMS developer guide, conditions-kms).
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = [local.kms_signing_alias]
    }
  }
}

resource "aws_iam_role_policy" "publisher" {
  name   = "${var.name}-publisher"
  role   = aws_iam_role.publisher.id
  policy = data.aws_iam_policy_document.publisher.json

  lifecycle {
    prevent_destroy = true
  }
}
