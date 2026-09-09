locals {
  oidc_sub = "token.actions.githubusercontent.com:sub"
  oidc_aud = "token.actions.githubusercontent.com:aud"
}

data "aws_iam_policy_document" "platform_ci_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = local.oidc_aud
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = local.oidc_sub
      values   = ["repo:${var.github_owner}/cloud-vending-machine:ref:refs/heads/main"]
    }
  }
}

data "aws_iam_policy_document" "platform_ci_permissions" {
  statement {
    sid     = "IAMManage"
    effect  = "Allow"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/portfolio-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/portfolio-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/portfolio-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }

  statement {
    sid     = "S3State"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [
      "arn:aws:s3:::${var.state_bucket}",
      "arn:aws:s3:::${var.state_bucket}/platform/aws/*",
    ]
  }
}

resource "aws_iam_role" "platform_ci" {
  name               = "portfolio-platform-aws-ci"
  assume_role_policy = data.aws_iam_policy_document.platform_ci_assume.json
}

resource "aws_iam_role_policy" "platform_ci" {
  name   = "platform-ci-permissions"
  role   = aws_iam_role.platform_ci.name
  policy = data.aws_iam_policy_document.platform_ci_permissions.json
}

data "aws_iam_policy_document" "provision_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = local.oidc_aud
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = local.oidc_sub
      values   = ["repo:${var.github_owner}/cloud-vending-machine:*"]
    }
  }
}

data "aws_iam_policy_document" "provision_permissions" {
  statement {
    sid       = "EC2Read"
    effect    = "Allow"
    actions   = ["ec2:Describe*", "ec2:Get*"]
    resources = ["*"]
  }

  statement {
    sid       = "EC2Create"
    effect    = "Allow"
    actions   = ["ec2:RunInstances", "ec2:CreateTags"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "DenyOversizedInstances"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]

    condition {
      test     = "StringNotEquals"
      variable = "ec2:InstanceType"
      values   = ["t3.micro", "t3.small"]
    }
  }

  statement {
    sid       = "EC2Terminate"
    effect    = "Allow"
    actions   = ["ec2:TerminateInstances", "ec2:DeleteTags"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/ManagedBy"
      values   = ["portal"]
    }
  }

  statement {
    sid       = "PassInstanceRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/portfolio-portal-instance"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "GetInstanceProfile"
    effect    = "Allow"
    actions   = ["iam:GetInstanceProfile"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/portfolio-portal-instance"]
  }

  statement {
    sid     = "TerraformState"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [
      "arn:aws:s3:::${var.state_bucket}",
      "arn:aws:s3:::${var.state_bucket}/requests/*",
    ]
  }

  statement {
    sid    = "S3PortalBuckets"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::portal-requests-*",
      "arn:aws:s3:::portal-requests-*/*",
    ]
  }

  statement {
    sid    = "IAMPortalUsers"
    effect = "Allow"
    actions = [
      "iam:CreateUser",
      "iam:DeleteUser",
      "iam:GetUser",
      "iam:ListUsers",
      "iam:TagUser",
      "iam:UntagUser",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:ListAccessKeys",
      "iam:PutUserPolicy",
      "iam:DeleteUserPolicy",
      "iam:GetUserPolicy",
      "iam:ListUserPolicies",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/portal/*"]
  }

  statement {
    sid    = "DenyPrivilegedIAM"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
      "iam:UpdateRole",
      "iam:DeleteRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:AttachUserPolicy",
      "iam:DetachUserPolicy",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:SetDefaultPolicyVersion",
      "organizations:*",
      "account:*",
      "sts:AssumeRole",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyOutOfRegion"
    effect    = "Deny"
    actions   = ["ec2:RunInstances", "s3:CreateBucket"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_role" "provision" {
  name               = "portfolio-portal-provision"
  assume_role_policy = data.aws_iam_policy_document.provision_assume.json
}

resource "aws_iam_role_policy" "provision" {
  name   = "portal-provision-policy"
  role   = aws_iam_role.provision.name
  policy = data.aws_iam_policy_document.provision_permissions.json
}
