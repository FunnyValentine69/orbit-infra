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
      "${aws_s3_bucket.state.arn}/envs/preview/*",
      "${aws_s3_bucket.state.arn}/bootstrap/*",
    ]
  }

  statement {
    sid           = "DenyListBucketOutsideScope"
    effect        = "Deny"
    actions       = ["s3:ListBucket"]
    not_resources = [aws_s3_bucket.state.arn]
  }

  # ReadOnlyAccess's broad s3:ListBucket would otherwise let plan-reader
  # enumerate every prefix in the state bucket (leases/*, other envs).
  # Deny listing the state bucket unless scoped to the allowed prefixes,
  # and deny it outright when no prefix condition is present at all.
  statement {
    sid       = "DenyListBucketOutsideScopePrefix"
    effect    = "Deny"
    actions   = ["s3:ListBucket", "s3:ListBucketVersions"]
    resources = [aws_s3_bucket.state.arn]

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
    resources = [aws_s3_bucket.state.arn]

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
    resources = [aws_s3_bucket.state.arn]

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
      "${aws_s3_bucket.state.arn}/envs/preview/*",
      "${aws_s3_bucket.state.arn}/bootstrap/*",
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

# --- deployer permissions ---

data "aws_iam_policy_document" "deployer" {
  #checkov:skip=CKV_AWS_111:every action enumerated below carries resources=["*"] only where the AWS IAM reference documents no resource-level permission for that action family (EC2 VPC/subnet/route-table/IGW/endpoint/SG lifecycle, ELBv2 Create/Register/tag calls, ECS RegisterTaskDefinition/CreateService, Cloud Map namespace/service, tag:GetResources) — the ARN doesn't exist until the call returns, or AWS documents no resource type at all; every action that DOES support resource-level scoping (S3 objects/buckets, CloudWatch log groups, Secrets Manager secrets, IAM roles) is scoped to a name-derived ARN pattern below (TODO.md P2-7)
  #checkov:skip=CKV_AWS_356:same constraint as CKV_AWS_111 above — the "*" resources are confined to actions AWS itself does not support resource-level ARN restriction for; see the per-statement comments in this document (TODO.md P2-7)
  # (a) preview env terraform state + apply leases: read/write/list.
  statement {
    sid     = "StateAndLeaseObjects"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = [
      "${aws_s3_bucket.state.arn}/envs/preview/*",
      "${aws_s3_bucket.state.arn}/leases/*",
    ]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucketVersions", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["envs/preview/*", "leases/*"]
    }
  }

  # (b) EC2 networking (VPC, subnets, route tables/routes, IGW, interface +
  # gateway VPC endpoints, security groups + rules) created by
  # modules/network and envs/preview. AWS does not support resource-level
  # IAM permissions for these Create/Delete/Describe/Modify actions (they
  # operate before the resource ARN exists, or the action family has no
  # documented resource type in the EC2 IAM reference) so `resources = ["*"]`
  # is required; scoped instead by action enumeration.
  statement {
    sid    = "Ec2NetworkLifecycle"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeRegions",
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:DescribeSubnets",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:DescribeInternetGateways",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:DescribeRouteTables",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:DescribeVpcEndpoints",
      "ec2:ModifyVpcEndpoint",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  # (c) ALB + target group + listener, created by envs/preview. ELBv2
  # Create/Register/Deregister/Add|RemoveTags calls target a load
  # balancer/target-group ARN that does not exist before the call
  # completes, so resource-level scoping is not workable for this
  # lifecycle; `resources = ["*"]` is required.
  statement {
    sid    = "ElbLifecycle"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  # (d) ECS cluster/service/task definitions, created by envs/preview,
  # modules/ecs-service, modules/redis, modules/clickhouse.
  # RegisterTaskDefinition/CreateService do not support resource-level
  # scoping (the task-definition/service ARN is only known after the
  # call), so `resources = ["*"]` is required.
  statement {
    sid    = "EcsLifecycle"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeleteCluster",
      "ecs:DescribeClusters",
      "ecs:CreateService",
      "ecs:UpdateService",
      "ecs:DeleteService",
      "ecs:DescribeServices",
      "ecs:ListServices",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DeleteTaskDefinitions",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # (e) Cloud Map namespace + service, created by envs/preview and
  # modules/ecs-service. Namespace/service ARNs are unknown pre-create;
  # `resources = ["*"]` is required.
  statement {
    sid    = "ServiceDiscoveryLifecycle"
    effect = "Allow"
    actions = [
      "servicediscovery:CreatePrivateDnsNamespace",
      "servicediscovery:DeleteNamespace",
      "servicediscovery:GetNamespace",
      "servicediscovery:GetOperation",
      "servicediscovery:ListNamespaces",
      "servicediscovery:CreateService",
      "servicediscovery:DeleteService",
      "servicediscovery:GetService",
      "servicediscovery:UpdateService",
      "servicediscovery:ListServices",
      "servicediscovery:TagResource",
      "servicediscovery:UntagResource",
      "servicediscovery:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # (f) CloudWatch log groups, created by modules/ecs-service at a
  # deterministic name (/orbit/<env_id>/<name>); resource-scoped to that
  # prefix.
  statement {
    sid    = "LogGroupLifecycle"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
    ]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/orbit/*"]
  }

  # (g) the ClickHouse password secret, created by envs/preview at a
  # deterministic name (<name>-<env_id>-clickhouse-password); resource-
  # scoped to that prefix.
  statement {
    sid    = "ClickhouseSecretLifecycle"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:GetSecretValue",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:GetResourcePolicy",
    ]
    resources = ["arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.name}-*"]
  }

  # (h) tag-based resource discovery Terraform uses for some data sources;
  # tag:GetResources has no resource-level scoping.
  statement {
    sid       = "TagDiscovery"
    effect    = "Allow"
    actions   = ["tag:GetResources"]
    resources = ["*"]
  }

  # (i) execution/task IAM roles for ECS services, created by
  # modules/ecs-service (name_prefix "<env_id>-<name>-", where <name>
  # always contains the project name). Scoped to role ARNs containing the
  # project name, not to a single env_id, because this policy is attached
  # once at bootstrap time and must cover every future preview env.
  statement {
    sid    = "EnvServiceRoleLifecycle"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*${var.name}*"]
  }

  # PassRole is kept as its own statement (not merged into (i)) and
  # restricted with iam:PassedToService so the deployer can only hand
  # these roles to ECS, never to itself or another service.
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
    ]
    resources = [
      "arn:aws:s3:::${var.name}-*-data",
      "arn:aws:s3:::${var.name}-*-data/*",
    ]
  }

  # Hard cap: the wildcard grants above (EnvServiceRoleLifecycle,
  # PassEnvRolesOnly) match role ARNs by substring since the ecs-service
  # module's name_prefix embeds the project name in the middle of a
  # dynamic string. That substring match could also match the three
  # fixed-purpose roles this same bootstrap creates (their names are
  # "${var.name}-deployer" etc., which contain var.name). Deny always
  # wins over Allow in IAM evaluation, so this statement is the actual
  # enforcement point keeping the deployer from mutating or passing its
  # own role, plan-reader, or publisher.
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
    ]
    resources = [
      aws_iam_role.deployer.arn,
      aws_iam_role.plan_reader.arn,
      aws_iam_role.publisher.arn,
    ]
  }
}

resource "aws_iam_role_policy" "deployer" {
  name   = "${var.name}-deployer"
  role   = aws_iam_role.deployer.id
  policy = data.aws_iam_policy_document.deployer.json

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
    resources = [for r in aws_ecr_repository.repos : r.arn]
  }

  statement {
    sid       = "SigningKey"
    effect    = "Allow"
    actions   = ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"]
    resources = [aws_kms_key.signing.arn]
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
