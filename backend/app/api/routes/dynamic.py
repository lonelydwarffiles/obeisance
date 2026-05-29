from uuid import UUID, uuid4

from fastapi import APIRouter, Header, HTTPException, status
from pydantic import BaseModel, Field

from app.services.notifications import notify_dom_petition

router = APIRouter(prefix="/dynamic", tags=["dynamic"])


class PetitionRequest(BaseModel):
    package: str = Field(min_length=1, max_length=255)
    reason: str = Field(min_length=1, max_length=2000)


class PetitionResponse(BaseModel):
    petition_id: UUID
    status: str
    package: str


@router.post("/petition", response_model=PetitionResponse, status_code=status.HTTP_202_ACCEPTED)
async def submit_petition(
    payload: PetitionRequest,
    x_mock_domme_user_id: UUID | None = Header(default=None),
) -> PetitionResponse:
    if x_mock_domme_user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing mock Dom user id",
        )

    petition_id = uuid4()
    await notify_dom_petition(
        dom_id=x_mock_domme_user_id,
        package_name=payload.package,
        reason=payload.reason,
        petition_id=petition_id,
    )

    return PetitionResponse(
        petition_id=petition_id,
        status="submitted",
        package=payload.package,
    )
