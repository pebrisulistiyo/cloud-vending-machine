# Where app-ci.yml pushes the portal image.
resource "google_artifact_registry_repository" "portal" {
  location      = var.gcp_region
  repository_id = "portal"
  format        = "DOCKER"
}
