"""Cloud Workflows execution + approval callback resolution.

The workflow does the heavy lifting: it waits on a human approval callback,
dispatches the provisioning GitHub Action, and updates Firestore statuses.
This module only starts executions and resolves callbacks.
"""
import json

import httpx

WORKFLOWS_API = "https://workflowexecutions.googleapis.com/v1"


def execute(project_id: str, location: str, workflow: str, argument: dict) -> str:
    """Start an execution, return its resource name (full API path)."""
    from google.cloud import workflows_v1

    client = workflows_v1.ExecutionsClient()
    parent = f"projects/{project_id}/locations/{location}/workflows/{workflow}"
    resp = client.create_execution(
        request={
            "parent": parent,
            "execution": {"argument": json.dumps(argument)},
        }
    )
    return resp.name


def build_callback_url(
    execution_name: str, callback_id: str, workflow: str = "request-lifecycle"
) -> str:
    """Compose the external URL an approver resolves through the portal API.

    execution_name is the full API path returned by execute()
    ("projects/P/locations/L/workflows/W/executions/E").
    """
    return f"{WORKFLOWS_API}/{execution_name}/callbacks/{callback_id}"


def resolve_callback(callback_url: str, body: dict) -> httpx.Response:
    """Resolve an approval callback with the given body.

    Cloud Workflows requires the original `X-Workflow-Callback-Url` header to
    be echoed back; the callback URL itself embeds the execution + callback id.
    """
    # Strip scheme/host and any `;param` suffix to get the API path.
    path = callback_url.split("workflowexecutions.googleapis.com", 1)[-1]
    path = path.split(";", 1)[0]
    return httpx.post(
        f"{WORKFLOWS_API}{path}",
        headers={"X-Workflow-Callback-Url": callback_url},
        json=body,
        timeout=30,
    )
