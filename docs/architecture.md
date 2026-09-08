# Architecture Notes

Deep-dive details that don't fit the README.

## Request lifecycle

```
pending to (approve) to provisioning to provisioned
        ↘ (reject)   to rejected
provisioned to (approve deprovision) to deprovisioning to deprovisioned
```

1. `POST /api/requests` validates (pydantic allowlists) and writes a
   `pending` document to Firestore, then starts the lifecycle workflow with
   a caller-generated `callback_id`.
2. The workflow creates the callback endpoint, then blocks on
   `events.await_callback` (24h timeout).
3. The app composes the external callback URL
   (`.../executions/{exec}/callbacks/{id}`) from the execution name and
   stores it on the Firestore document.
4. `POST /approve` (approval token) resolves the callback with
   `{approved: true}`, Cloud Workflows wakes up, reads the GitHub PAT from
   Secret Manager, dispatches `provision.yml` with the request inputs, and
   marks the document `provisioning`.
5. `provision.yml` re-validates inputs (untrusted dispatch), runs Terraform
   against per-request state (`requests/{id}/terraform.tfstate`), and POSTs
   outputs to `/api/requests/{id}/complete` (callback token), marking
   `provisioned`.
6. Deprovisioning is the same state machine with `deprovision.yml`
   (destroy + delete the state key).

Failures anywhere post-dispatch call `/complete` with `status: failed` and
the run URL as the message.

## Why per-request state (ADR-011)

One giant state file for all portal-created resources would couple every
request to every other: a destroy for request A would plan against B's
resources. Per-request state keys make each request independently
provisionable and independently destroyable, and cleanup is one `s3 rm`.

## The single PAT (ADR-010 trade-off)

Workflows cannot assume the GitHub OIDC identity of a repo (only GitHub
Actions jobs can). So the dispatch hop needs a token. A fine-grained PAT
with exactly `actions: write` on this repo, rotated in Secret Manager, is
the smallest credential that does it. Alternatives and why not:

- **GitHub App installation token**, smaller scope, more moving parts
  (private key, JWT minting, installation ids). The PAT is the right
  trade-off at portfolio scale.
- **Direct GCPtoAWS workload identity federation**, removes the hop but
  moves provisioning logic into the container and loses the public audit
  artifact of a workflow run.
- **Terraform Cloud / service catalog**, adds a paid dependency to a demo.

## Security boundaries

| Component | Can do |
|-----------|--------|
| Cloud Run SA | Firestore r/w, start workflows, read secrets, nothing else |
| Workflows SA | Firestore r/w, read `github-pat`, nothing else |
| AWS provision role | EC2/S3 lifecycle, IAM users in `portal-*`, PassRole on the shared instance role, state bucket under `requests/` |
| GCP CI SA (WIF) | editor on the project (documented first-cut) |
| Requester | submit + read their own request, nothing else |
| Approver | approve/reject/deprovision via token |
