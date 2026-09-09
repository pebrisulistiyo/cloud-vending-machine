# Enable everything the platform touches, in one place.
locals {
  apis = toset([
    "run.googleapis.com",
    "workflows.googleapis.com",
    "firestore.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "billingbudgets.googleapis.com",
    "monitoring.googleapis.com",
  ])
}

resource "google_project_service" "apis" {
  for_each                   = local.apis
  project                    = var.gcp_project_id
  service                    = each.key
  disable_dependent_services = true
}
