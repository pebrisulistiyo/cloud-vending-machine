# The portal's request database. Firestore native mode, single region
# (the whole system is Singapore, so no multi-region bill).
resource "google_firestore_database" "default" {
  project     = var.gcp_project_id
  name        = "(default)"
  location_id = var.gcp_region
  type        = "FIRESTORE_NATIVE"
}
