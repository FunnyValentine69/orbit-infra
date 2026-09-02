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
        "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:pull_request",
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

  statement {
    sid    = "DenySecretsAndParams"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "kms:Decrypt",
      "lambda:GetFunction",
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
  #checkov:skip=CKV_AWS_107:deployer environment-mutation statement is an explicit-action placeholder; tightened at Phase 2 when the module API surface is known (TODO.md P2-4)
  #checkov:skip=CKV_AWS_108:deployer environment-mutation statement is an explicit-action placeholder; tightened at Phase 2 when the module API surface is known (TODO.md P2-4)
  #checkov:skip=CKV_AWS_109:deployer environment-mutation statement is an explicit-action placeholder; tightened at Phase 2 when the module API surface is known (TODO.md P2-4)
  #checkov:skip=CKV_AWS_111:deployer environment-mutation statement is an explicit-action placeholder; tightened at Phase 2 when the module API surface is known (TODO.md P2-4)
  #checkov:skip=CKV_AWS_356:deployer environment-mutation statement is an explicit-action placeholder; tightened at Phase 2 when the module API surface is known (TODO.md P2-4)
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

  # (b) placeholder for environment mutation rights; tighten at Phase 2
  # once the module's exact API surface is known.
  statement {
    sid    = "EnvironmentMutationPlaceholder"
    effect = "Allow"
    actions = [
      "ec2:*",
      "ecs:*",
      "elasticloadbalancing:*",
      "logs:*",
      "servicediscovery:*",
      "secretsmanager:*",
      "tag:GetResources",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassEnvRolesOnly"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-env-*"]
  }

  statement {
    sid       = "EnvBucketsOnly"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${var.name}-env-*", "arn:aws:s3:::${var.name}-env-*/*"]
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
