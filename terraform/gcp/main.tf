# Per-request GCP entry point. Same shape as terraform/aws: per-request
# state (prefix = requests/{request_id}), called only from the workflow.

terraform {
  required_version = ">= 1.15"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # bucket + prefix arrive via -backend-config in the workflow:
  #   prefix = requests/{request_id}
  backend "gcs" {}
}

variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "asia-southeast1"
}

variable "request_id" {
  description = "Portal request id."
  type        = string
}

variable "resource_type" {
  description = "gce | gcs | service_account (validated by the workflow before dispatch)."
  type        = string
}

variable "instance_size" {
  description = "GCE machine type for gce requests."
  type        = string
  default     = ""
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "request" {
  source        = "../modules/gcp-request"
  project_id    = var.project_id
  region        = var.region
  request_id    = var.request_id
  resource_type = var.resource_type
  instance_size = var.instance_size
}

output "request" {
  description = "Provisioned resources, sent to the portal callback."
  value       = module.request.outputs
  sensitive   = true
}
