# The portal itself: Cloud Run, scale-to-zero, public URL. It's a demo,
# so request creation is public; the approval gate protects the actual
# provisioning.

resource "google_cloud_run_v2_service" "portal" {
  name     = "portal"
  location = var.gcp_region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloudrun.email

    containers {
      image = var.portal_image

      ports {
        container_port = 8080
      }

      env {
        name  = "APP_MODE"
        value = "gcp"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.gcp_project_id
      }
      env {
        name  = "GCP_LOCATION"
        value = var.gcp_region
      }
      env {
        name  = "GITHUB_OWNER"
        value = var.github_owner
      }
      env {
        name  = "APPROVAL_TOKEN"
        value = ""
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.approval_token.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "CALLBACK_TOKEN"
        value = ""
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.callback_token.secret_id
            version = "latest"
          }
        }
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }
}

# Public invocation for the demo. The approval token + workflow dispatch are
# the real gates; the form itself is meant to be reachable.
resource "google_cloud_run_service_iam_member" "public" {
  location = google_cloud_run_v2_service.portal.location
  project  = var.gcp_project_id
  service  = google_cloud_run_v2_service.portal.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
