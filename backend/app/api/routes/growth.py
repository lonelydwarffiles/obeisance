from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import InviteLink
from app.services.billing import create_invite_link, get_growth_stats, process_signup

router = APIRouter(prefix="/growth", tags=["growth"])


class CreateInviteResponse(BaseModel):
    slug: str
    max_uses: int
    current_uses: int
    is_active: bool


class SignupRequest(BaseModel):
    invite_slug: str


class SignupResponse(BaseModel):
    slug: str
    current_uses: int
    max_uses: int
    is_active: bool


class GrowthDashboardResponse(BaseModel):
    active_subs: int
    total_slots: int
    invite_slug: str | None = None
    remaining_uses: int | None = None


class RequestAccessRequest(BaseModel):
    contact: str | None = None
    note: str | None = None


class RequestAccessResponse(BaseModel):
    status: str


@router.post("/create-link", response_model=CreateInviteResponse, status_code=status.HTTP_201_CREATED)
async def create_link(
    db: AsyncSession = Depends(get_db),
    x_mock_domme_user_id: UUID | None = Header(default=None),
) -> CreateInviteResponse:
    if x_mock_domme_user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing mock Domme user id")

    invite = await create_invite_link(x_mock_domme_user_id, db)
    return CreateInviteResponse(
        slug=invite.slug,
        max_uses=invite.max_uses,
        current_uses=invite.current_uses,
        is_active=invite.is_active,
    )


@router.post("/signup", response_model=SignupResponse, status_code=status.HTTP_200_OK)
async def signup(payload: SignupRequest, db: AsyncSession = Depends(get_db)) -> SignupResponse:
    invite = await process_signup(payload.invite_slug, db)
    return SignupResponse(
        slug=invite.slug,
        current_uses=invite.current_uses,
        max_uses=invite.max_uses,
        is_active=invite.is_active,
    )


@router.get("/stats", response_model=GrowthDashboardResponse)
async def growth_stats(
    db: AsyncSession = Depends(get_db),
    x_mock_domme_user_id: UUID | None = Header(default=None),
) -> GrowthDashboardResponse:
    if x_mock_domme_user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing mock Domme user id")

    stats = await get_growth_stats(x_mock_domme_user_id, db)
    invite_result = await db.execute(
        select(InviteLink)
        .where(InviteLink.creator_id == x_mock_domme_user_id)
        .order_by(desc(InviteLink.is_active), desc(InviteLink.id))
    )
    invite = invite_result.scalars().first()

    remaining_uses = None
    invite_slug = None
    if invite is not None:
        invite_slug = invite.slug
        remaining_uses = max(invite.max_uses - invite.current_uses, 0)

    return GrowthDashboardResponse(
        active_subs=stats.active_subs,
        total_slots=stats.total_slots,
        invite_slug=invite_slug,
        remaining_uses=remaining_uses,
    )


@router.post("/request-access", response_model=RequestAccessResponse, status_code=status.HTTP_202_ACCEPTED)
async def request_access(payload: RequestAccessRequest) -> RequestAccessResponse:
    _ = payload
    return RequestAccessResponse(status="central_notified")
