variable "gcp_project_id" {
  description = "GCP project everything lives in."
  type        = string

  validation {
    condition     = length(trimspace(var.gcp_project_id)) > 0
    error_message = "gcp_project_id must not be empty."
  }
}

variable "gcp_region" {
  description = "GCP region. Mirrors the AWS region (Singapore)."
  type        = string
  default     = "asia-southeast1"
}

variable "github_owner" {
  description = "GitHub owner whose Actions repos may use the WIF pool."
  type        = string
  default     = "pebrisulistiyo"
}

variable "billing_account_id" {
  description = "Billing account for the budget guardrail (format: XXXXXX-XXXXXX-XXXXXX)."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Z]{6}-[0-9A-Z]{6}-[0-9A-Z]{6}$", var.billing_account_id))
    error_message = "billing_account_id must look like XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "alert_email" {
  description = "Email that receives budget alerts."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "portal_image" {
  description = "Artifact Registry image the Cloud Run service runs (pushed by app-ci.yml)."
  type        = string
  default     = "PLACEHOLDER-docker.pkg.dev/PLACEHOLDER/portal/portal:latest"
}
