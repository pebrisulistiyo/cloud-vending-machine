variable "aws_region" {
  description = "AWS region for all platform resources."
  type        = string
  default     = "ap-southeast-1"
}

variable "state_bucket" {
  description = "S3 bucket that holds Terraform state for this project."
  type        = string
}

variable "github_owner" {
  description = "GitHub owner whose Actions workflows may assume platform roles."
  type        = string
  default     = "pebrisulistiyo"
}
