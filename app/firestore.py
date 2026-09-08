"""Request persistence.

GCP mode (default): Firestore.
Local mode (APP_MODE=local): in-memory dict, lets the whole approval flow be
demonstrated and tested with no cloud at all.
"""
import os
from datetime import datetime, timezone

from . import schemas


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class RequestStore:
    def __init__(self) -> None:
        self.mode = os.getenv("APP_MODE", "gcp")
        self._mem: dict[str, dict] = {}
        self._db = None
        if self.mode == "gcp":
            # Lazy import so local mode never needs GCP libraries installed.
            from google.cloud import firestore

            self._db = firestore.Client()

    # -- shared interface ----------------------------------------------------
    def create(self, req: schemas.RequestCreate) -> schemas.Request:
        record = schemas.Request(
            request_id=req.request_id,
            requester=req.requester,
            cloud=req.cloud.value,
            resource_type=req.resource_type.value,
            params={
                "instance_size": req.instance_size,
                "region": (
                    schemas.DEFAULT_AWS_REGION
                    if req.cloud is schemas.Cloud.aws
                    else schemas.DEFAULT_GCP_REGION
                ),
            },
            status=schemas.RequestStatus.pending,
            created_at=_now(),
        )
        self._put(record.model_dump())
        return record

    def get(self, request_id: str) -> schemas.Request | None:
        raw = self._get(request_id)
        return schemas.Request(**raw) if raw else None

    def update(self, request_id: str, **fields) -> schemas.Request | None:
        current = self._get(request_id)
        if not current:
            return None
        current.update(fields)
        current["updated_at"] = _now()
        self._put(current)
        return schemas.Request(**current)

    def list_by_status(self, status: schemas.RequestStatus) -> list[schemas.Request]:
        return [r for r in self._list() if r.status == status]

    def list_all(self) -> list[schemas.Request]:
        return self._list()

    # -- backends ------------------------------------------------------------
    def _put(self, record: dict) -> None:
        if self.mode == "gcp":
            self._db.collection("requests").document(record["request_id"]).set(record)
        else:
            self._mem[record["request_id"]] = record

    def _get(self, request_id: str) -> dict | None:
        if self.mode == "gcp":
            doc = self._db.collection("requests").document(request_id).get()
            return doc.to_dict() if doc.exists else None
        return self._mem.get(request_id)

    def _list(self) -> list[schemas.Request]:
        if self.mode == "gcp":
            docs = self._db.collection("requests").stream()
            return [schemas.Request(**d.to_dict()) for d in docs]
        return [schemas.Request(**r) for r in self._mem.values()]
