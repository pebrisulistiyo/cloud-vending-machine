"""Request validation, the first layer of defense.

Everything a user can type is allowlisted here before it gets anywhere near a
cloud. GitHub Actions validates again in provision.yml (defense in depth:
workflow_dispatch inputs are untrusted too).
"""
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator

# Random-enough and URL-safe; also matches the regex enforced in provision.yml.
REQUEST_ID_REGEX = r"^[a-z0-9-]{8,36}$"

# Instance sizes are allowlisted per cloud, requesters may only pick these.
AWS_SIZES = ("t3.micro", "t3.small")
GCP_SIZES = ("e2-micro", "e2-small")

DEFAULT_AWS_REGION = "ap-southeast-1"
DEFAULT_GCP_REGION = "asia-southeast1"


class Cloud(str, Enum):
    aws = "aws"
    gcp = "gcp"


class ResourceType(str, Enum):
    ec2 = "ec2"
    s3 = "s3"
    iam_user = "iam_user"
    gce = "gce"
    gcs = "gcs"
    service_account = "service_account"


# Which resource types belong to which cloud.
RESOURCE_TYPES_BY_CLOUD = {
    Cloud.aws: {ResourceType.ec2, ResourceType.s3, ResourceType.iam_user},
    Cloud.gcp: {ResourceType.gce, ResourceType.gcs, ResourceType.service_account},
}


class RequestCreate(BaseModel):
    request_id: str = Field(pattern=REQUEST_ID_REGEX)
    requester: str = Field(min_length=2, max_length=64)
    cloud: Cloud
    resource_type: ResourceType
    instance_size: str | None = None

    @model_validator(mode="after")
    def check_resource_cloud_coherence(self) -> "RequestCreate":
        if self.resource_type not in RESOURCE_TYPES_BY_CLOUD[self.cloud]:
            raise ValueError(
                f"{self.resource_type.value} is not provisionable on {self.cloud.value}"
            )
        return self

    @model_validator(mode="after")
    def check_instance_size(self) -> "RequestCreate":
        needs_size = self.resource_type in (ResourceType.ec2, ResourceType.gce)
        if needs_size:
            allowed = AWS_SIZES if self.cloud is Cloud.aws else GCP_SIZES
            if self.instance_size not in allowed:
                raise ValueError(
                    f"instance_size must be one of {', '.join(allowed)} for "
                    f"{self.resource_type.value}"
                )
        return self


class RequestStatus(str, Enum):
    pending = "pending"
    approved = "approved"
    provisioning = "provisioning"
    provisioned = "provisioned"
    rejected = "rejected"
    failed = "failed"
    deprovisioning = "deprovisioning"
    deprovisioned = "deprovisioned"


class Request(BaseModel):
    request_id: str
    requester: str
    cloud: str
    resource_type: str
    params: dict[str, Any]
    status: RequestStatus
    created_at: str
    updated_at: str | None = None
    callback_url: str | None = None
    workflow_execution: str | None = None
    github_run_url: str | None = None
    outputs: dict[str, Any] | None = None
    message: str | None = None


class Approval(BaseModel):
    approved: bool = False
    rejected: bool = False
    note: str | None = None

    @model_validator(mode="after")
    def exactly_one_decision(self) -> "Approval":
        if self.approved == self.rejected:
            raise ValueError("exactly one of approved/rejected must be true")
        return self


class Completion(BaseModel):
    status: Literal["provisioned", "failed", "deprovisioned"]
    outputs: dict[str, Any] | None = None
    message: str | None = None
