"""Cloud Vending Machine portal.

Flow: user requests a resource on AWS or GCP, an approver approves, Cloud
Workflows dispatches a GitHub Action, Terraform provisions it with
per-request state, and the requester gets their resource back.

APP_MODE=local runs the same flow with an in-memory store and simulated
provisioning (no cloud, no workflow), used by tests and local demos.
"""
import os
import secrets

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi import Request as HttpRequest
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from . import schemas, workflows
from .firestore import RequestStore

APP_MODE = os.getenv("APP_MODE", "gcp")
APP_VERSION = os.getenv("APP_VERSION", "dev")
GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID", "")
GCP_LOCATION = os.getenv("GCP_LOCATION", "asia-southeast1")
GITHUB_OWNER = os.getenv("GITHUB_OWNER", "pebrisulistiyo")
WORKFLOW_NAME = "request-lifecycle"

# Local-mode defaults keep the demo runnable with zero setup; in GCP mode
# these come from Secret Manager-backed env vars on Cloud Run.
APPROVAL_TOKEN = os.getenv("APPROVAL_TOKEN", "dev-approval-token")
CALLBACK_TOKEN = os.getenv("CALLBACK_TOKEN", "dev-callback-token")

app = FastAPI(title="Cloud Vending Machine")
store = RequestStore()
templates = Jinja2Templates(directory=os.path.join(os.path.dirname(__file__), "templates"))


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------
def require_approval_token(
    x_approval_token: str | None = Header(default=None),
) -> None:
    if x_approval_token != APPROVAL_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid approval token")


def require_callback_token(
    x_callback_token: str | None = Header(default=None),
) -> None:
    if x_callback_token != CALLBACK_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid callback token")


def _public(record: schemas.Request) -> dict:
    """The public view of a request: never leaks callback urls or tokens."""
    data = record.model_dump()
    data.pop("callback_url", None)
    data.pop("workflow_execution", None)
    return data


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------
@app.get("/", response_class=HTMLResponse)
async def index(request: HttpRequest):
    return templates.TemplateResponse(request, "index.html")


@app.get("/admin", response_class=HTMLResponse)
async def admin(request: HttpRequest):
    return templates.TemplateResponse(request, "admin.html")


@app.get("/requests/{request_id}", response_class=HTMLResponse)
async def request_page(request: HttpRequest, request_id: str):
    record = store.get(request_id)
    if not record:
        return templates.TemplateResponse(
            request, "not-found.html", {"request_id": request_id}
        )
    return templates.TemplateResponse(
        request, "request.html", {"r": _public(record)}
    )


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
@app.post("/api/requests", status_code=201)
async def create_request(body: schemas.RequestCreate):
    if store.get(body.request_id):
        raise HTTPException(status_code=409, detail="request_id already exists")

    store.create(body)

    if APP_MODE == "gcp":
        _start_workflow(body.request_id, phase="provision", workflow_file="provision.yml")

    return _public(store.get(body.request_id))


@app.get("/api/requests/{request_id}")
async def get_request(request_id: str):
    record = store.get(request_id)
    if not record:
        raise HTTPException(status_code=404, detail="request not found")
    return _public(record)


@app.get("/api/requests")
async def list_requests(_: None = Depends(require_approval_token)):
    return [_public(r) for r in store.list_all()]


@app.post("/api/requests/{request_id}/approve")
async def approve_request(
    request_id: str,
    body: schemas.Approval,
    _: None = Depends(require_approval_token),
):
    record = store.get(request_id)
    if not record:
        raise HTTPException(status_code=404, detail="request not found")
    if record.status != schemas.RequestStatus.pending:
        raise HTTPException(
            status_code=409, detail=f"request is already {record.status.value}"
        )

    if APP_MODE == "gcp":
        # Resolve the workflow's approval callback; the workflow then dispatches
        # the GitHub Action, which applies Terraform and POSTs /complete.
        if not record.callback_url:
            raise HTTPException(
                status_code=409,
                detail="no approval callback pending (workflow may still be starting)",
            )
        resp = workflows.resolve_callback(
            record.callback_url, {"approved": body.approved, "rejected": body.rejected}
        )
        if resp.status_code >= 400:
            raise HTTPException(status_code=502, detail=resp.text)
        store.update(request_id, message=body.note or "approval sent")
    else:
        # Local simulation: skip the workflow entirely.
        if body.rejected:
            store.update(
                request_id,
                status=schemas.RequestStatus.rejected,
                message=body.note or "rejected",
            )
        else:
            store.update(
                request_id,
                status=schemas.RequestStatus.provisioned,
                message=body.note or "provisioned (local mode: no cloud calls)",
                outputs={"note": "local-mode simulation", "requester": record.requester},
            )

    return _public(store.get(request_id))


@app.post("/api/requests/{request_id}/reject")
async def reject_request(
    request_id: str,
    _: None = Depends(require_approval_token),
):
    return await approve_request(
        request_id,
        schemas.Approval(approved=False, rejected=True, note="rejected"),
    )


@app.post("/api/requests/{request_id}/deprovision")
async def deprovision_request(
    request_id: str,
    _: None = Depends(require_approval_token),
):
    """Tear down a provisioned request. Same approval gate as provisioning
    deleting something deserves at least as much review as creating it."""
    record = store.get(request_id)
    if not record:
        raise HTTPException(status_code=404, detail="request not found")
    if record.status != schemas.RequestStatus.provisioned:
        raise HTTPException(
            status_code=409, detail=f"only provisioned requests can be deprovisioned (current: {record.status.value})"
        )

    if APP_MODE == "gcp":
        _start_workflow(request_id, phase="deprovision", workflow_file="deprovision.yml")
    else:
        store.update(
            request_id,
            status=schemas.RequestStatus.deprovisioned,
            message="deprovisioned (local mode: no cloud calls)",
            outputs=None,
        )

    return _public(store.get(request_id))


@app.post("/api/requests/{request_id}/complete")
async def complete_request(
    request_id: str,
    body: schemas.Completion,
    _: None = Depends(require_callback_token),
):
    """Called by the provisioning GitHub Action when Terraform finishes."""
    record = store.get(request_id)
    if not record:
        raise HTTPException(status_code=404, detail="request not found")

    fields = {"status": schemas.RequestStatus(body.status), "outputs": body.outputs}
    if body.message:
        fields["message"] = body.message
    store.update(request_id, **fields)
    return _public(store.get(request_id))


@app.get("/health")
async def health():
    return {"status": "ok", "mode": APP_MODE, "version": APP_VERSION}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------
def _start_workflow(request_id: str, phase: str, workflow_file: str) -> None:
    """Start the lifecycle workflow and store the approval callback URL."""
    record = store.get(request_id)
    assert record is not None

    callback_id = secrets.token_hex(16)
    execution = workflows.execute(
        GCP_PROJECT_ID,
        GCP_LOCATION,
        WORKFLOW_NAME,
        {
            "project_id": GCP_PROJECT_ID,
            "location": GCP_LOCATION,
            "request_id": request_id,
            "callback_id": callback_id,
            "github_owner": GITHUB_OWNER,
            "workflow_file": workflow_file,
            "phase": phase,
            "cloud": record.cloud,
            "resource_type": record.resource_type,
            "instance_size": record.params.get("instance_size") or "",
        },
    )
    store.update(
        request_id,
        workflow_execution=execution,
        callback_url=workflows.build_callback_url(execution, callback_id, WORKFLOW_NAME),
    )
