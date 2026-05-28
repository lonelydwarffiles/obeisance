from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class SharedNoteResponse(BaseModel):
    id: UUID
    device_id: UUID
    content: str
    updated_at: datetime


class SharedNoteUpdate(BaseModel):
    content: str


class DossierResponse(BaseModel):
    id: UUID
    domme_id: UUID
    device_id: UUID
    private_notes: str
    last_updated: datetime


class DossierUpdate(BaseModel):
    private_notes: str
