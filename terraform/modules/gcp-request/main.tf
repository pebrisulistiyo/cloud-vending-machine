# Per-request GCP resources. Code-first like everything GCP: valid today,
# applied once the platform/gcp foundation is live.

terraform {
  required_version = ">= 1.15"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

variable "project_id" {
  description = "GCP project resources are created in."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "asia-southeast1"
}

variable "request_id" {
  description = "Portal request id (also the Terraform state prefix)."
  type        = string
}

variable "resource_type" {
  description = "gce | gcs | service_account"
  type        = string

  validation {
    condition     = contains(["gce", "gcs", "service_account"], var.resource_type)
    error_message = "resource_type must be one of gce, gcs, service_account."
  }
}

variable "instance_size" {
  description = "GCE machine type (allowlisted upstream by the portal)."
  type        = string
  default     = "e2-micro"
}

data "google_compute_image" "debian" {
  family  = "debian-13"
  project = "debian-cloud"
}

# --- GCE: Debian, no external IP (agent-only access, same posture as AWS).
resource "google_compute_instance" "this" {
  count = var.resource_type == "gce" ? 1 : 0

  project      = var.project_id
  name         = "portal-${var.request_id}"
  machine_type = var.instance_size
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 20
    }
  }

  network_interface {
    network = "default"
  }

  labels = { "portal-request" = var.request_id }
}

# --- GCS: globally unique name (GCS buckets share one namespace).
resource "google_storage_bucket" "this" {
  count = var.resource_type == "gcs" ? 1 : 0

  project                  = var.project_id
  name                     = "portal-requests-${var.request_id}"
  location                 = var.region
  public_access_prevention = "enforced"

  labels = { "portal-request" = var.request_id }
}

# --- Service account: portal-sa-* namespace, no project-level roles granted
# here (viewer binding happens at apply time if requested; keep minimal).
# NOTE: real GCP *user* provisioning requires Cloud Identity (paid), an
# limitation documented in the README.
resource "google_service_account" "this" {
  count = var.resource_type == "service_account" ? 1 : 0

  project      = var.project_id
  account_id   = "portal-sa-${var.request_id}"
  display_name = "Portal requested SA ${var.request_id}"
}

output "outputs" {
  description = "Provisioned resources, keyed by type. Delivered to the portal callback."
  sensitive   = true
  value = {
    gce = var.resource_type == "gce" ? {
      instance_name = google_compute_instance.this[0].name
      access        = "gcloud compute ssh / console (no external IP configured)"
    } : null
    gcs = var.resource_type == "gcs" ? {
      bucket_name = google_storage_bucket.this[0].name
    } : null
    service_account = var.resource_type == "service_account" ? {
      email = google_service_account.this[0].email
    } : null
  }
}
