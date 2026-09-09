# Resource Governance

This document defines the rules for what users can request through the vending machine,
what gets enforced at each layer, and why each constraint exists.

Enforcement is defense-in-depth across three layers:

```
Layer 1: Portal API      — Pydantic schema validates every request on submission
Layer 2: GitHub Actions  — provision.yml re-validates all inputs (untrusted dispatch)
Layer 3: Terraform       — module variables + provider constraints, last line of defense
```

---

## AWS

### Allowed resource types

| Type | Description |
|------|-------------|
| `ec2` | Compute instance, SSM-managed |
| `s3` | Private object storage bucket |
| `iam_user` | IAM user with read-only policy |

### EC2 — instance size allowlist

Users may only select:

| Size | vCPU | RAM | Use case |
|------|------|-----|----------|
| `t3.micro` | 2 | 1 GB | Dev / low-traffic |
| `t3.small` | 2 | 2 GB | Light workloads |

**Why:** t3.micro and t3.small are the smallest burstable sizes that are still useful.
Larger sizes (t3.medium, m5.*, c5.*) are not available to prevent cost runaway from a
forgotten instance. EC2 instances are the most expensive resource in this catalog.

**Enforced at:**
- `app/schemas.py` — `AWS_SIZES = ("t3.micro", "t3.small")`, validated in `check_instance_size`
- `provision.yml` — bash `case` statement re-validates `instance_size`

### EC2 — security posture

- **No SSH key pairs.** Access is via SSM Session Manager only (`http_tokens = "required"`
  enforces IMDSv2, preventing SSRF attacks against instance metadata).
- **Shared instance profile only.** EC2 instances get the pre-created `portfolio-portal-instance`
  role (provisioned by terraform-bootstrap, not by this project). That role has SSM access
  and nothing else — no S3, no IAM, no cross-account.
- **Patch Group tag.** Every instance is tagged `Patch Group: demo`, which ties it into
  the cloud-patch-automation pipeline. Security patches apply automatically.
- **No public IP.** Instances launch without an Elastic IP or public DNS entry. Access
  is internal via SSM only.

### S3 — security posture

- **All public access blocked.** `block_public_acls`, `block_public_policy`,
  `ignore_public_acls`, and `restrict_public_buckets` are all `true`. A requester
  cannot make objects public, even with explicit ACLs.
- **Bucket name is namespaced.** Format: `portal-requests-{request_id}-{account_id}`.
  This prevents bucket-squatting (guessing a bucket name before a request is approved).

### IAM user — privilege constraints

Provisioned IAM users receive a **read-only inline policy** with two statements:

| Sid | Actions | Resources |
|-----|---------|-----------|
| `S3Read` | `s3:GetObject`, `s3:ListBucket` | `portal-requests-*` buckets only |
| `Describe` | `ec2:Describe*`, `ssm:Describe*` | `*` (read-only, no state changes) |

**Why read-only?** The portal is a vending machine for temporary, scoped credentials.
Granting write or admin access through an automated flow with no per-action review is
a security anti-pattern. If a requester needs write access, an approver must provision
it manually outside this system.

**No console access.** The user has no password, only an access key pair. Console login
requires a separate password set by an admin.

**Namespace enforcement.** The portal's IAM provision role (terraform-bootstrap) uses an
IAM policy condition that restricts it to creating users under the `/portal/` path and
the `portal-*` name prefix. The Terraform module enforces the same naming. Neither the
portal nor the requester can create users outside this namespace.

### Per-requester quota

The portal API enforces **10 `POST /api/requests` per minute per IP** (slowapi rate limiter).
There is no per-user quota on simultaneous provisioned resources — an approver's judgement
is the gate. This is intentional: the approver sees all pending requests and can reject
duplicates.

---

## GCP

### Allowed resource types

| Type | Description |
|------|-------------|
| `gce` | Compute instance, OS Login / no external IP |
| `gcs` | Private object storage bucket |
| `service_account` | GCP service account, no project roles |

### GCE — machine type allowlist

Users may only select:

| Type | vCPU | RAM | Use case |
|------|------|-----|----------|
| `e2-micro` | 2 (shared) | 1 GB | Dev / demos |
| `e2-small` | 2 (shared) | 2 GB | Light workloads |

**Why:** e2-micro is free-tier eligible. e2-small is the next step up without crossing
into non-burstable territory. Larger machine types (n2, c2, a2) carry GPU/memory costs
that are not appropriate for a self-service catalog.

**Enforced at:**
- `app/schemas.py` — `GCP_SIZES = ("e2-micro", "e2-small")`, validated in `check_instance_size`
- `provision.yml` — bash `case` statement re-validates `instance_size`

### GCE — security posture

- **No external IP.** `network_interface` has no `access_config` block. The instance
  has only an internal RFC 1918 address. Access is via `gcloud compute ssh` through IAP
  (Identity-Aware Proxy tunneling) or the Cloud Console.
- **No project-level service account.** The instance runs on the Compute Engine default
  SA, which has no project-level roles granted by this module. (The default SA has
  read-only metadata access only at demo scale.)
- **Boot disk: Debian 13.** A current, supported OS with automatic security updates via
  OS Config Agent.
- **Labeled for audit.** Every instance is labeled `portal-request: {request_id}`,
  making it trivially findable in Cloud Console and Cloud Asset Inventory.

### GCS — security posture

- **Public access prevention: enforced.** `public_access_prevention = "enforced"` is a
  GCP org-policy-level setting applied in Terraform. Even an IAM binding of
  `allUsers:objectViewer` is rejected at the API level.
- **No CORS, no lifecycle, no retention lock.** The bucket is plain private storage.
  Any special configuration must be applied manually by someone with bucket-level IAM.

### Service account — privilege constraints

Provisioned service accounts receive **zero project-level IAM roles**. The account is
created in the namespace `portal-sa-{request_id}`. It has no keys, no bindings.

**Why no roles?** A service account without bindings is inert — it cannot call any GCP
API. If a requester needs a service account with specific permissions, an approver must
grant roles manually after reviewing the intended use. The vending machine creates the
identity; role assignment is an out-of-band approval step.

**No keys.** The module does not create service account keys (`google_service_account_key`).
Keys are long-lived credentials that can be exfiltrated. Workload Identity Federation
(the pattern used by this project's own CI) is the correct key-free alternative.

**Note on GCP users:** Provisioning a GCP human user identity requires Cloud Identity
(a paid product). The vending machine cannot create `user:` principals — only service
accounts. This is a documented limitation, not an oversight.

---

## Cross-cloud rules

### Resource lifetime

All provisioned resources have an **8-hour automatic expiry**. When a request
transitions to `provisioned`, the system sets `expires_at = provisioned_time + 8h`.
An hourly cron (`expire-resources.yml`) decommissions any resource past its expiry
by dispatching `deprovision.yml` directly (no human approval needed for cleanup).

Approvers may manually deprovision any resource before the 8-hour limit via the
admin panel.

**Why 8 hours?** Long enough for a full working day of demo use, short enough that a
forgotten instance from a morning session is gone by end of day. The limit is set in
`app/firestore.py` as `RESOURCE_LIFETIME = timedelta(hours=8)` and can be changed
with a single-line edit.

### What users cannot request

- Admin / root credentials (`AdministratorAccess`, `roles/owner`, `roles/editor`)
- Large compute (`t3.medium+`, `n2`, `c2`, GPU instances)
- Anything not in the explicit `ResourceType` enum in `app/schemas.py`
- Resources in regions outside the defaults (ap-southeast-1 / asia-southeast1)
- More than one instance per request (the Terraform module uses `count = 1`)

### What approvers review before approving

The admin panel shows the full request record including `cloud`, `resource_type`,
`instance_size`, and `requester`. Approvers are expected to:

1. Verify the requester is known (no anonymous requests should be approved)
2. Confirm the resource type matches the stated need
3. Check for duplicate pending requests from the same requester
4. Reject requests that ask for a resource type that could be misused (e.g., IAM users
   for automation scripts should go through a proper onboarding flow instead)
