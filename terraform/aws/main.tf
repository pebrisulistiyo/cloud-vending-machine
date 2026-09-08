# Per-request AWS entry point. Invoked only by provision.yml/deprovision.yml
# with the request id as the state key, each request gets its own isolated
# state, so deprovisioning one never disturbs another (ADR-011).

terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket + region + key arrive via -backend-config in the workflow:
  #   key = requests/{request_id}/terraform.tfstate
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-1"
}

variable "request_id" {
  description = "Portal request id."
  type        = string
}

variable "resource_type" {
  description = "ec2 | s3 | iam_user (validated by the workflow before dispatch)."
  type        = string
}

variable "instance_size" {
  description = "EC2 instance type for ec2 requests."
  type        = string
  default     = ""
}

variable "instance_role_name" {
  description = "Shared SSM instance role pre-created by terraform-bootstrap."
  type        = string
  default     = "portfolio-portal-instance"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "portal"
      RequestId = var.request_id
    }
  }
}

module "request" {
  source             = "../modules/aws-request"
  request_id         = var.request_id
  resource_type      = var.resource_type
  instance_size      = var.instance_size
  instance_role_name = var.instance_role_name
}

output "request" {
  description = "Provisioned resources, sent to the portal callback."
  value       = module.request.outputs
  sensitive   = true
}
