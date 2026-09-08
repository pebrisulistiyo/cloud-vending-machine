"""API tests, run in local mode (in-memory store, no cloud calls).

    python -m pytest app/tests -q
"""
import os

os.environ["APP_MODE"] = "local"

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

APPROVAL = {"X-Approval-Token": "dev-approval-token"}
CALLBACK = {"X-Callback-Token": "dev-callback-token"}


def _create(**overrides):
    payload = {
        "request_id": "demo-ec2-0001",
        "requester": "Ada Lovelace",
        "cloud": "aws",
        "resource_type": "ec2",
        "instance_size": "t3.micro",
    }
    payload.update(overrides)
    return client.post("/api/requests", json=payload)


def test_health():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json()["mode"] == "local"
    assert res.json()["version"] == "dev"  # default when no build arg injected


def test_create_valid_request():
    res = _create()
    assert res.status_code == 201
    body = res.json()
    assert body["status"] == "pending"
    assert body["resource_type"] == "ec2"
    assert "callback_url" not in body


def test_create_rejects_duplicate_id():
    assert _create(request_id="dup-test-0001").status_code == 201
    assert _create(request_id="dup-test-0001").status_code == 409


def test_create_rejects_bad_request_id():
    assert _create(request_id="UPPER!!!").status_code == 422


def test_create_rejects_invalid_size():
    assert _create(instance_size="m5.24xlarge").status_code == 422


def test_create_rejects_missing_size():
    payload = {
        "request_id": "demo-ec2-0002",
        "requester": "Ada",
        "cloud": "aws",
        "resource_type": "ec2",
    }
    assert client.post("/api/requests", json=payload).status_code == 422


def test_create_rejects_cloud_mismatch():
    assert _create(resource_type="gce", instance_size="e2-micro").status_code == 422


def test_approve_flow_local_mode():
    _create(request_id="demo-ec2-0003")
    res = client.post(
        "/api/requests/demo-ec2-0003/approve",
        headers=APPROVAL,
        json={"approved": True},
    )
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "provisioned"
    assert body["outputs"] is not None


def test_approve_requires_token():
    _create(request_id="demo-ec2-0004")
    res = client.post(
        "/api/requests/demo-ec2-0004/approve",
        json={"approved": True},
    )
    assert res.status_code == 403


def test_reject_flow_local_mode():
    _create(request_id="demo-ec2-0005")
    res = client.post(
        "/api/requests/demo-ec2-0005/reject",
        headers=APPROVAL,
    )
    assert res.status_code == 200
    assert res.json()["status"] == "rejected"


def test_approval_body_needs_exactly_one_decision():
    _create(request_id="demo-ec2-0006")
    res = client.post(
        "/api/requests/demo-ec2-0006/approve",
        headers=APPROVAL,
        json={"approved": True, "rejected": True},
    )
    assert res.status_code == 422


def test_complete_requires_callback_token():
    _create(request_id="demo-ec2-0007")
    res = client.post(
        "/api/requests/demo-ec2-0007/complete",
        json={"status": "provisioned", "outputs": {"instance_id": "i-123"}},
    )
    assert res.status_code == 403

    res = client.post(
        "/api/requests/demo-ec2-0007/complete",
        headers=CALLBACK,
        json={"status": "provisioned", "outputs": {"instance_id": "i-123"}},
    )
    assert res.status_code == 200
    assert res.json()["outputs"]["instance_id"] == "i-123"


def test_unknown_request_404():
    assert client.get("/api/requests/nope-nope").status_code == 404
    assert (
        client.post(
            "/api/requests/nope-nope/approve",
            headers=APPROVAL,
            json={"approved": True},
        ).status_code
        == 404
    )


def test_admin_list_requires_token():
    assert client.get("/api/requests").status_code == 403
    res = client.get("/api/requests", headers=APPROVAL)
    assert res.status_code == 200
    assert isinstance(res.json(), list)


def test_deprovision_local_mode():
    _create(request_id="demo-ec2-0008")
    client.post(
        "/api/requests/demo-ec2-0008/approve",
        headers=APPROVAL,
        json={"approved": True},
    )
    res = client.post("/api/requests/demo-ec2-0008/deprovision", headers=APPROVAL)
    assert res.status_code == 200
    assert res.json()["status"] == "deprovisioned"
    assert res.json()["outputs"] is None


def test_deprovision_requires_provisioned():
    _create(request_id="demo-ec2-0009")
    res = client.post("/api/requests/demo-ec2-0009/deprovision", headers=APPROVAL)
    assert res.status_code == 409


def test_deprovision_requires_token():
    _create(request_id="demo-ec2-0010")
    res = client.post("/api/requests/demo-ec2-0010/deprovision")
    assert res.status_code == 403
