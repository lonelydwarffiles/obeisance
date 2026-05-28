from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field


class SubmissionCreate(BaseModel):
    hardware_uuid: str
    device_model: str
    os_version: str
    battery_percentage: int = Field(ge=0, le=100)
    static_link_id: str


class SubmissionResponse(BaseModel):
    id: UUID
    status: str


class SubmissionAction(str, Enum):
    approve = "approve"
    reject = "reject"


class SubmissionReview(BaseModel):
    action: SubmissionAction
