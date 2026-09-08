terraform {
  required_version = ">= 1.15"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # CODE-FIRST: applied when the GCP account exists. This module's own state
  # lives in a manually-created GCS bucket (backend.hcl.example), the same
  # chicken-and-egg as terraform-bootstrap on AWS. It then creates the shared
  # state bucket every other repo uses (statebucket.tf).
  backend "gcs" {}
}
