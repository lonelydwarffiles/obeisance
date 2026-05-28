from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CandidatePublishRequest(BaseModel):
    anonymized_interests: dict = Field(default_factory=dict)


class CandidateProfileResponse(BaseModel):
    id: UUID
    device_id: UUID
    anonymized_interests: dict
    readiness_score: float
    is_published: bool
    updated_at: datetime
