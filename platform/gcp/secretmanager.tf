# Portal secrets.
#
# CODE-FIRST NOTE: versions are created with placeholder values so the whole
# platform is describable in one apply. ROTATE ALL THREE before the first
# real deployment (console or gcloud, lifecycle ignores the data, so
# Terraform will not fight you).
resource "google_secret_manager_secret" "approval_token" {
  secret_id = "approval-token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "approval_token" {
  secret      = google_secret_manager_secret.approval_token.id
  secret_data = "change-me-rotate-before-first-deploy"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret" "callback_token" {
  secret_id = "callback-token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "callback_token" {
  secret      = google_secret_manager_secret.callback_token.id
  secret_data = "change-me-rotate-before-first-deploy"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# The single non-OIDC credential in the system (ADR-010): a fine-grained PAT
# scoped to actions:write on the cloud-vending-machine repo. Workflows uses it
# to dispatch provision.yml/deprovision.yml.
resource "google_secret_manager_secret" "github_pat" {
  secret_id = "github-pat"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "github_pat" {
  secret      = google_secret_manager_secret.github_pat.id
  secret_data = "github_pat_CHANGE_ME"

  lifecycle {
    ignore_changes = [secret_data]
  }
}
