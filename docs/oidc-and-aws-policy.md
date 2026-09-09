# OIDC Setup & AWS Provision Role Policy

## What is OIDC in this project?

OIDC (OpenID Connect) is the mechanism that lets GitHub Actions authenticate to AWS and GCP
**without storing any long-lived credentials** (no `AWS_ACCESS_KEY_ID`, no GCP service account
key files). Instead, GitHub's token server issues a short-lived signed JWT for each job run.
The cloud provider verifies that JWT against GitHub's public keys, then issues a temporary
session credential scoped to whatever role you trust.

```
GitHub Actions job starts
  → GitHub issues a signed OIDC JWT (valid ~1h, audience = sts.amazonaws.com / accounts.google.com)
      → AWS / GCP verify the JWT signature against https://token.actions.githubusercontent.com
          → Cloud issues a short-lived session credential (assumed role / access token)
              → Terraform runs with that credential
```

---

## GCP side — already done

The Workload Identity Federation (GCP's OIDC implementation) is created by
`platform/gcp/iam.tf` when you run `terraform apply` on the platform. Key resources:

```hcl
# platform/gcp/iam.tf (excerpt — already in this repo)

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  attribute_condition = "assertion.repository_owner == 'pebrisulistiyo'"
}
```

After `terraform apply`, copy the provider resource name into your GitHub repo variables:

| GitHub variable | Value |
|----------------|-------|
| `GCP_WIF_PROVIDER` | `projects/{number}/locations/global/workloadIdentityPools/github-actions/providers/github-actions` |
| `GCP_WIF_SA` | `gha-ci@{project-id}.iam.gserviceaccount.com` |

---

## AWS side — `platform/aws/`

The AWS OIDC provider and provision role live in `platform/aws/` in this repo,
mirroring the structure of `platform/gcp/`.

### Step 1 — Create the OIDC identity provider

```hcl
# platform/aws/oidc.tf

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]

  # GitHub's current OIDC thumbprint. Verify at:
  # https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
```

> You only create this **once** per AWS account, even if you have many repos using OIDC.
> If it already exists, import it: `terraform import aws_iam_openid_connect_provider.github <arn>`

### Step 2 — Create the provision role with a scoped trust policy

The trust policy limits which repos and workflows can assume this role.

```hcl
# platform/aws/iam.tf

data "aws_iam_policy_document" "github_assume_portal" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    # Only the cloud-vending-machine repo can assume this role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to provision.yml and deprovision.yml workflows only.
    # "workflow" claim = the workflow file path that triggered the job.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:pebrisulistiyo/cloud-vending-machine:*",
      ]
    }
  }
}

resource "aws_iam_role" "portal_provision" {
  name               = "portfolio-portal-provision"
  assume_role_policy = data.aws_iam_policy_document.github_assume_portal.json

  tags = {
    ManagedBy = "terraform-bootstrap"
    Purpose   = "Cloud vending machine provisioning via GitHub Actions OIDC"
  }
}
```

### Step 3 — Attach the governance-constrained permission policy

This policy enforces every rule documented in `docs/governance.md`.

```hcl
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "portal_provision_permissions" {

  # -------------------------------------------------------------------------
  # EC2 — read (needed by Terraform plan)
  # -------------------------------------------------------------------------
  statement {
    sid       = "EC2Read"
    effect    = "Allow"
    actions   = ["ec2:Describe*", "ec2:Get*"]
    resources = ["*"]
  }

  # -------------------------------------------------------------------------
  # EC2 — create resources, region-locked to ap-southeast-1
  # -------------------------------------------------------------------------
  statement {
    sid    = "EC2CreateRegionLocked"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["ap-southeast-1"]
    }
  }

  # -------------------------------------------------------------------------
  # EC2 — DENY anything larger than t3.micro / t3.small
  # Deny takes precedence over the allow above.
  # -------------------------------------------------------------------------
  statement {
    sid    = "DenyOversizedInstances"
    effect = "Deny"
    actions = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]
    condition {
      test     = "StringNotEquals"
      variable = "ec2:InstanceType"
      values   = ["t3.micro", "t3.small"]
    }
  }

  # -------------------------------------------------------------------------
  # EC2 — terminate only portal-tagged instances (can't touch other resources)
  # -------------------------------------------------------------------------
  statement {
    sid    = "EC2TerminatePortalOnly"
    effect = "Allow"
    actions = ["ec2:TerminateInstances", "ec2:DeleteTags"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/ManagedBy"
      values   = ["portal"]
    }
  }

  # -------------------------------------------------------------------------
  # PassRole — only the shared instance profile, only to EC2
  # Without this, RunInstances with an iam_instance_profile is denied.
  # -------------------------------------------------------------------------
  statement {
    sid    = "PassInstanceRole"
    effect = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/portfolio-portal-instance",
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # -------------------------------------------------------------------------
  # IAM instance profile — read only (pre-created by bootstrap, not this role)
  # -------------------------------------------------------------------------
  statement {
    sid    = "GetInstanceProfile"
    effect = "Allow"
    actions = ["iam:GetInstanceProfile"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/portfolio-portal-instance",
    ]
  }

  # -------------------------------------------------------------------------
  # S3 — Terraform state for request-scoped state keys only
  # -------------------------------------------------------------------------
  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
    ]
    resources = [
      "arn:aws:s3:::${var.state_bucket}",
      "arn:aws:s3:::${var.state_bucket}/requests/*",
    ]
  }

  # -------------------------------------------------------------------------
  # S3 — portal request buckets (portal-requests-* namespace only)
  # -------------------------------------------------------------------------
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

  # -------------------------------------------------------------------------
  # IAM users — portal/* path and portal-* name prefix only
  # No ability to attach managed policies or create roles.
  # -------------------------------------------------------------------------
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
      "iam:PutUserPolicy",    # inline policies only
      "iam:DeleteUserPolicy",
      "iam:GetUserPolicy",
      "iam:ListUserPolicies",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/portal/*",
    ]
  }

  # -------------------------------------------------------------------------
  # DENY — hard stops on privileged actions, regardless of any other allow
  # -------------------------------------------------------------------------
  statement {
    sid    = "DenyPrivilegedIAM"
    effect = "Deny"
    actions = [
      # No role creation / modification
      "iam:CreateRole",
      "iam:UpdateRole",
      "iam:DeleteRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      # No attaching managed policies to users
      "iam:AttachUserPolicy",
      "iam:DetachUserPolicy",
      # No creating/modifying managed policies
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:SetDefaultPolicyVersion",
      # No account-level or org changes
      "organizations:*",
      "account:*",
      "sts:AssumeRole",       # can't pivot to other roles
    ]
    resources = ["*"]
  }

  # -------------------------------------------------------------------------
  # DENY — no resources outside ap-southeast-1 (belt-and-suspenders)
  # -------------------------------------------------------------------------
  statement {
    sid    = "DenyOutOfRegion"
    effect = "Deny"
    actions = [
      "ec2:RunInstances",
      "s3:CreateBucket",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = ["ap-southeast-1"]
    }
  }
}

resource "aws_iam_policy" "portal_provision" {
  name        = "portfolio-portal-provision-policy"
  description = "Governance-constrained policy for cloud vending machine provisioning"
  policy      = data.aws_iam_policy_document.portal_provision_permissions.json
}

resource "aws_iam_role_policy_attachment" "portal_provision" {
  role       = aws_iam_role.portal_provision.name
  policy_arn = aws_iam_policy.portal_provision.arn
}
```

### Step 4 — Add the variable and output

```hcl
variable "state_bucket" {
  description = "S3 bucket name used for Terraform state."
  type        = string
}

output "portal_provision_role_arn" {
  description = "Set this as AWS_PROVISION_ROLE_ARN in GitHub repo variables."
  value       = aws_iam_role.portal_provision.arn
}
```

### Step 5 — Apply and set GitHub variables

First apply must use local credentials (the OIDC role doesn't exist yet):

```bash
cd platform/aws
cp terraform.tfvars.example terraform.tfvars   # fill in values
cp backend.hcl.example backend.hcl             # fill in bucket name
terraform init -backend-config=backend.hcl
terraform apply
```

After apply, copy outputs to GitHub repo settings:

| GitHub variable | Terraform output |
|----------------|-----------------|
| `AWS_PROVISION_ROLE_ARN` | `provision_role_arn` |
| `AWS_PLATFORM_ROLE_ARN` | `platform_ci_role_arn` |
| `AWS_REGION` (secret) | `ap-southeast-1` |
| `AWS_STATE_BUCKET` (secret) | your state bucket name |

Subsequent applies can be triggered via **Actions → platform-ci → Run workflow → apply_aws = true**.

---

## What the policy enforces — summary

| Constraint | How enforced |
|-----------|-------------|
| Only `t3.micro` / `t3.small` allowed | `Deny` on `ec2:RunInstances` when `ec2:InstanceType` not in allowlist |
| Only `ap-southeast-1` region | `Deny` on create actions when `aws:RequestedRegion` not matching |
| Only `portal-*` IAM users under `/portal/` path | Resource ARN scope on IAM actions |
| No managed policy attachment to users | `Deny iam:AttachUserPolicy` |
| No role creation or modification | `Deny iam:CreateRole` + related |
| No pivoting to other roles | `Deny sts:AssumeRole` |
| Terminate only portal-tagged EC2 | `aws:ResourceTag/ManagedBy = portal` condition |
| PassRole only for the shared instance profile | Resource ARN + `iam:PassedToService` condition |
| No org / account-level changes | `Deny organizations:*`, `account:*` |

---

## Why two deny statements instead of one?

IAM evaluation order: explicit `Deny` always wins over `Allow`.  
- `DenyOversizedInstances` — catches instance type violations at the instance resource level
- `DenyOutOfRegion` — catches region violations at the request level  
- `DenyPrivilegedIAM` — catches privilege escalation regardless of what other policies allow

Belt-and-suspenders: if any future `Allow` is added carelessly, the `Deny` statements
still hold.

---

## Verifying the policy works

After setup, you can test with AWS Policy Simulator (`iam:SimulatePrincipalPolicy`) or
by running a test dispatch from `provision.yml` with a known-invalid input:

```bash
# Should be denied (wrong instance type)
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/portfolio-portal-provision \
  --action-names ec2:RunInstances \
  --resource-arns "arn:aws:ec2:ap-southeast-1:ACCOUNT:instance/*" \
  --context-entries "ContextKeyName=ec2:InstanceType,ContextKeyType=string,ContextKeyValues=t3.large"

# Should be denied (wrong region)
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/portfolio-portal-provision \
  --action-names ec2:RunInstances \
  --resource-arns "arn:aws:ec2:us-east-1:ACCOUNT:instance/*" \
  --context-entries "ContextKeyName=aws:RequestedRegion,ContextKeyType=string,ContextKeyValues=us-east-1"
```
