from uuid import UUID

from pydantic import BaseModel


class TermResponse(BaseModel):
    id: UUID
    category: str
    term: str
    status: str


class TermSuggestRequest(BaseModel):
    category: str
    term: str
