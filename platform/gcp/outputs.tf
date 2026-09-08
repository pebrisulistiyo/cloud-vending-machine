output "portal_url" {
  description = "Public URL of the Cloud Run service."
  value       = google_cloud_run_v2_service.portal.uri
}

output "wif_pool_name" {
  description = "WIF pool resource name (feeds GCP_WIF_PROVIDER repo variable)."
  value       = google_iam_workload_identity_pool.github.name
}

output "wif_provider_name" {
  description = "WIF provider resource name (feeds GCP_WIF_PROVIDER repo variable)."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "gha_ci_service_account" {
  description = "CI service account email (feeds GCP_WIF_SA repo variable)."
  value       = google_service_account.gha_ci.email
}

output "state_bucket" {
  description = "Shared GCP Terraform state bucket (feeds GCP_STATE_BUCKET repo variable)."
  value       = google_storage_bucket.tfstate.name
}
