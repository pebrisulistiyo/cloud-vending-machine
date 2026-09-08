# The shared GCP Terraform state bucket: every other repo's backend and every
# per-request portal state live here (this module's own state is the one
# manually created bucket, see backend.hcl.example).
resource "google_storage_bucket" "tfstate" {
  name                     = "eko-portfolio-tfstate-gcp"
  location                 = var.gcp_region
  public_access_prevention = "enforced"

  versioning {
    enabled = true
  }
}
