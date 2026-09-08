# ---------------------------------------------------------------------------
# Service accounts, least privilege, one per job.
# ---------------------------------------------------------------------------

# Cloud Run runtime: read/write Firestore, start workflows, read secrets.
resource "google_service_account" "cloudrun" {
  account_id   = "portal-run"
  display_name = "Portal Cloud Run runtime"
}

resource "google_project_iam_member" "cloudrun_datastore" {
  project = var.gcp_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloudrun.email}"
}

resource "google_project_iam_member" "cloudrun_workflows_invoker" {
  project = var.gcp_project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.cloudrun.email}"
}

resource "google_project_iam_member" "cloudrun_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloudrun.email}"
}

# Workflows executor: update Firestore statuses, read the GitHub PAT.
resource "google_service_account" "workflows" {
  account_id   = "portal-workflows"
  display_name = "Portal Cloud Workflows executor"
}

resource "google_project_iam_member" "workflows_datastore" {
  project = var.gcp_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.workflows.email}"
}

resource "google_project_iam_member" "workflows_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.workflows.email}"
}

# ---------------------------------------------------------------------------
# CI service account + Workload Identity Federation, no keys, ever.
# One SA shared by the three multi-cloud repos; Editor is a documented
# first-cut, scoped down as hardening.
# ---------------------------------------------------------------------------
resource "google_service_account" "gha_ci" {
  account_id   = "gha-ci"
  display_name = "GitHub Actions CI (WIF)"
}

resource "google_project_iam_member" "gha_ci_editor" {
  project = var.gcp_project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.gha_ci.email}"
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions pool"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "gha_ci_wif" {
  for_each = toset([
    "cloud-patch-automation",
    "cloud-vending-machine",
    "multi-cloud-serverless",
  ])

  service_account_id = google_service_account.gha_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${each.key}"
}
