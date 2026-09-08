# Local Development & GCP Runbook

## Run the portal locally (no cloud at all)

`APP_MODE=local` swaps Firestore for an in-memory store and skips Cloud
Workflows entirely, the full request to approve/reject to provisioned flow
works with zero setup:

```bash
cd app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt

APP_MODE=local uvicorn app.main:app --reload
# to http://localhost:8000
#   Approve/reject token (local default): dev-approval-token
#   Callback token (local default):          dev-callback-token
```

```bash
pytest tests -q     # 17 tests, no network
ruff check .        # lint
```

## GCP unblock checklist (when the account arrives)

### 1. One-time manual steps

```bash
gcloud auth application-default login
gcloud config set project <PROJECT_ID>

# This module's own state bucket (chicken-and-egg, like terraform-bootstrap):
gsutil mb -l asia-southeast1 gs://eko-portfolio-tfstate-platform
gsutil versioning set on gs://eko-portfolio-tfstate-platform
```

### 2. Apply the platform

```bash
cd platform/gcp
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars   # project id, billing account, email, portal_image
terraform init -backend-config=backend.hcl
terraform apply
```

This creates: Firestore, Artifact Registry, Cloud Run service (placeholder
image, the first deploy happens next), the lifecycle workflow, WIF pool +
provider + CI SA, Secret Manager secrets, the shared state bucket, and the
$10/mo budget.

### 3. Rotate secrets, then deploy the app

1. In Secret Manager, add a new version of `approval-token`, `callback-token`
   and `github-pat` (fine-grained PAT with `actions: write` on this repo).
2. Set repository variables (Settings to Actions to Variables):

| Variable | Value |
|----------|-------|
| `GCP_PROJECT_ID` | your project id |
| `GCP_REGION` | `asia-southeast1` |
| `GCP_WIF_PROVIDER` | `terraform output wif_provider_name` |
| `GCP_WIF_SA` | `terraform output gha_ci_service_account` |
| `GCP_STATE_BUCKET` | `terraform output state_bucket` |
| `GCP_PLATFORM_STATE_BUCKET` | `eko-portfolio-tfstate-platform` |
| `PORTAL_URL` | `terraform output portal_url` |

3. Repository secret `PORTAL_CALLBACK_TOKEN` = the same value as Secret
   Manager `callback-token`.
4. Push to `main` to `app-ci.yml` builds, Trivy-scans, pushes to Artifact
   Registry, deploys Cloud Run, smoke-tests.

### 4. Done, the portal is live

Update the `portal_image` tfvar so a future `terraform apply` doesn't revert
the image to the placeholder.

## AWS-only E2E (works today, no portal needed)

Scenario B in [demo-script.md](demo-script.md): manual `workflow_dispatch`
on provision.yml provisions an EC2 instance / S3 bucket / IAM user with the
scoped provision role, then deprovision.yml tears it down. This is the
shareable evidence artifact while GCP is still code-first.
