# Demo Script

Two scenarios, word-for-word. Scenario A needs the GCP platform live; Scenario B works today with only the AWS side (terraform-bootstrap applied).

## Scenario A, the full portal (GCP live)

**Setup:** portal deployed on Cloud Run; you hold the approval token; a second device (or incognito window) is the "requester".

1. **Requester:** open the portal URL to fill the form: name, AWS, EC2, `t3.micro` to Submit. Note the request id.
2. **Screenshots:** the request page showing `pending`; Firestore console showing the document; Workflows console showing the execution waiting on its callback.
3. **Approver:** open `/admin`, enter the approval token, Load to click **Approve** on the request.
4. **Screenshots:** the GitHub Actions `provision` run kicking off (public link!); the terraform apply output in the run logs; the request page now showing `provisioned` with `instance_id`.
5. **Proof in AWS console:** the EC2 instance exists, SSM-managed, tagged `Patch Group=demo`, and appears in Patch Manager compliance later.
6. **Approver:** click **Deprovision** to same gate to run destroys the instance and deletes its state key. Request page shows `deprovisioned`.
7. **One GCP request for multi-cloud flavor:** requester picks GCP, GCS to approve to bucket exists in the GCP console.

## Scenario B, AWS E2E without the portal (works today)

1. GitHub to Actions to `provision` to Run workflow:
   - `request_id: demo-ec2-0001`
   - `cloud: aws`, `resource_type: ec2`, `instance_size: t3.micro`
2. **Screenshots:** the run logs, input validation, `terraform init` with the per-request state key, apply output, the `complete` callback skipped (no PORTAL_URL yet, shown as skipped).
3. AWS console: the instance exists. Run `aws ssm send-command --document-name AWS-RunPatchBaseline ...` or just note the `Patch Group` tag.
4. Run `deprovision` the same way to instance gone, state key deleted.
5. Repeat for `s3` and `iam_user` if the demo needs variety (IAM user shows the credentials-in-outputs behavior).

## Rejection path (both scenarios)

Submit a request, approve nothing, instead **Reject** it in `/admin` to status `rejected`, no GitHub run ever dispatched. This screenshot proves the gate is real, not theater.

## What NOT to say in the demo

- Don't claim GCP is live if Scenario A wasn't run, the README says code-first, say it too.
- Don't show the IAM user's secret key twice; note it's shown once and deleted on deprovision.
