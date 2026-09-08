# Per-request AWS resources. Every request type is behind a count so one
# module serves all of them, and the provision role (terraform-bootstrap)
# stays the only permission boundary.

variable "request_id" {
  description = "Portal request id (also the Terraform state key)."
  type        = string
}

variable "resource_type" {
  description = "ec2 | s3 | iam_user"
  type        = string

  validation {
    condition     = contains(["ec2", "s3", "iam_user"], var.resource_type)
    error_message = "resource_type must be one of ec2, s3, iam_user."
  }
}

variable "instance_size" {
  description = "EC2 instance type (allowlisted upstream by the portal)."
  type        = string
  default     = "t3.micro"
}

variable "instance_role_name" {
  description = "Shared SSM instance role pre-created by terraform-bootstrap."
  type        = string
  default     = "portfolio-portal-instance"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_instance_profile" "portal_instance" {
  name = var.instance_role_name
}

locals {
  tags = {
    Name      = "portal-${var.request_id}"
    RequestId = var.request_id
  }
}

# --- EC2: SSM-managed, no key pairs. The "Patch Group" tag ties it into the
# cloud-patch-automation project, requested VMs get patched like everything else.
resource "aws_instance" "this" {
  count = var.resource_type == "ec2" ? 1 : 0

  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = var.instance_size
  iam_instance_profile = data.aws_iam_instance_profile.portal_instance.name

  metadata_options {
    http_tokens = "required"
  }

  tags = merge(local.tags, { "Patch Group" = "demo" })
}

# --- S3: globally-unique name (bucket names are a global namespace).
resource "aws_s3_bucket" "this" {
  count  = var.resource_type == "s3" ? 1 : 0
  bucket = "portal-requests-${var.request_id}-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  count  = var.resource_type == "s3" ? 1 : 0
  bucket = aws_s3_bucket.this[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM user: portal-* namespace (matches the provision role's policy),
# read-only inline policy, one access key delivered back to the requester.
resource "aws_iam_user" "this" {
  count = var.resource_type == "iam_user" ? 1 : 0
  name  = "portal-${var.request_id}"
  path  = "/portal/"
  tags  = local.tags
}

resource "aws_iam_user_policy" "read_only" {
  count = var.resource_type == "iam_user" ? 1 : 0
  name  = "portal-read-only"
  user  = aws_iam_user.this[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::portal-requests-*",
          "arn:aws:s3:::portal-requests-*/*",
        ]
      },
      {
        Sid      = "Describe"
        Effect   = "Allow"
        Action   = ["ec2:Describe*", "ssm:Describe*"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_access_key" "this" {
  count = var.resource_type == "iam_user" ? 1 : 0
  user  = aws_iam_user.this[0].name
}

output "outputs" {
  description = "Provisioned resources, keyed by type. Delivered to the portal callback."
  sensitive   = true
  value = {
    ec2 = var.resource_type == "ec2" ? {
      instance_id = aws_instance.this[0].id
      access      = "SSM Session Manager (no SSH keys)"
      patch_group = "demo"
    } : null
    s3 = var.resource_type == "s3" ? {
      bucket_name = aws_s3_bucket.this[0].bucket
    } : null
    iam_user = var.resource_type == "iam_user" ? {
      user_name         = aws_iam_user.this[0].name
      access_key_id     = aws_iam_access_key.this[0].id
      secret_access_key = aws_iam_access_key.this[0].secret
    } : null
  }
}
