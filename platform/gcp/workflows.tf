# The request-lifecycle workflow: approval gate to GitHub dispatch.
# Source YAML lives next to the app (workflows/request-lifecycle.yaml).
resource "google_workflows_workflow" "request_lifecycle" {
  name            = "request-lifecycle"
  project         = var.gcp_project_id
  region          = var.gcp_region
  description     = "Provision/deprovision state machine: human approval to GitHub Actions dispatch."
  service_account = google_service_account.workflows.id

  source_contents = file("${path.module}/../../workflows/request-lifecycle.yaml")
}
