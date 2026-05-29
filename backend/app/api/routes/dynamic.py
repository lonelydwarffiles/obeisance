from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user, require_domme
from app.db.database import get_db
from app.db.models import Device, Petition, PetitionStatus, User
from app.services.audit import record_audit_event
from app.services.notifications import notify_dom_petition

router = APIRouter(prefix="/dynamic", tags=["dynamic"])


class PetitionRequest(BaseModel):
    package: str = Field(min_length=1, max_length=255)
    reason: str = Field(min_length=1, max_length=2000)
    device_id: UUID | None = None


class PetitionResponse(BaseModel):
    petition_id: UUID
    status: str
    package: str
    approved_minutes: int | None = None


class PetitionDecisionResponse(BaseModel):
    petition_id: UUID
    status: str
    approved_minutes: int | None = None


class PetitionSummary(BaseModel):
    petition_id: UUID
    status: str
    package: str
    reason: str
    created_at: datetime
    approved_minutes: int | None


@router.post("/petition", response_model=PetitionResponse, status_code=status.HTTP_202_ACCEPTED)
async def submit_petition(
    payload: PetitionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    x_target_dom_id: UUID | None = Header(default=None, alias="X-Target-Dom-Id"),
    x_mock_domme_user_id: UUID | None = Header(default=None, alias="X-Mock-Domme-User-Id"),
) -> PetitionResponse:
    dom_id = x_target_dom_id or x_mock_domme_user_id
    if dom_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing target Dom id",
        )

    dom = (await db.execute(select(User).where(User.id == dom_id))).scalar_one_or_none()
    if dom is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Target Dom not found")

    if payload.device_id is not None:
        device = (await db.execute(select(Device).where(Device.id == payload.device_id))).scalar_one_or_none()
        if device is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")

    petition = Petition(
        dom_id=dom_id,
        requester_user_id=current_user.id,
        device_id=payload.device_id,
        package_name=payload.package,
        reason=payload.reason,
        status=PetitionStatus.submitted,
    )
    db.add(petition)
    await db.flush()

    await notify_dom_petition(
        dom_id=dom_id,
        package_name=payload.package,
        reason=payload.reason,
        petition_id=petition.id,
    )

    await record_audit_event(
        db=db,
        actor_user_id=current_user.id,
        device_id=payload.device_id,
        action="petition_submitted",
        target_type="petition",
        target_id=str(petition.id),
        metadata={"package": payload.package, "dom_id": str(dom_id)},
    )

    await db.commit()

    return PetitionResponse(
        petition_id=petition.id,
        status=petition.status.value,
        package=payload.package,
    )


@router.post(
    "/petition/{petition_id}/approve-15m",
    response_model=PetitionDecisionResponse,
    status_code=status.HTTP_200_OK,
)
async def approve_petition_15m(
    petition_id: UUID,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> PetitionDecisionResponse:
    petition = (await db.execute(select(Petition).where(Petition.id == petition_id))).scalar_one_or_none()
    if petition is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Petition not found")
    if petition.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Petition does not belong to this Dom")

    petition.status = PetitionStatus.approved
    petition.approved_minutes = 15
    petition.decided_at = datetime.now(timezone.utc)

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=petition.device_id,
        action="petition_approved",
        target_type="petition",
        target_id=str(petition.id),
        metadata={"approved_minutes": 15},
    )
    await db.commit()

    return PetitionDecisionResponse(
        petition_id=petition.id,
        status=petition.status.value,
        approved_minutes=petition.approved_minutes,
    )


@router.post(
    "/petition/{petition_id}/deny",
    response_model=PetitionDecisionResponse,
    status_code=status.HTTP_200_OK,
)
async def deny_petition(
    petition_id: UUID,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> PetitionDecisionResponse:
    petition = (await db.execute(select(Petition).where(Petition.id == petition_id))).scalar_one_or_none()
    if petition is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Petition not found")
    if petition.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Petition does not belong to this Dom")

    petition.status = PetitionStatus.denied
    petition.approved_minutes = None
    petition.decided_at = datetime.now(timezone.utc)

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=petition.device_id,
        action="petition_denied",
        target_type="petition",
        target_id=str(petition.id),
        metadata={},
    )
    await db.commit()

    return PetitionDecisionResponse(
        petition_id=petition.id,
        status=petition.status.value,
        approved_minutes=petition.approved_minutes,
    )


@router.post(
    "/petition/{petition_id}/expire",
    response_model=PetitionDecisionResponse,
    status_code=status.HTTP_200_OK,
)
async def expire_petition(
    petition_id: UUID,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> PetitionDecisionResponse:
    petition = (await db.execute(select(Petition).where(Petition.id == petition_id))).scalar_one_or_none()
    if petition is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Petition not found")
    if petition.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Petition does not belong to this Dom")

    petition.status = PetitionStatus.expired
    petition.approved_minutes = None
    petition.decided_at = datetime.now(timezone.utc)

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=petition.device_id,
        action="petition_expired",
        target_type="petition",
        target_id=str(petition.id),
        metadata={},
    )
    await db.commit()

    return PetitionDecisionResponse(
        petition_id=petition.id,
        status=petition.status.value,
        approved_minutes=petition.approved_minutes,
    )


@router.get("/petition", response_model=list[PetitionSummary], status_code=status.HTTP_200_OK)
async def list_petitions(
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> list[PetitionSummary]:
    petitions = (
        await db.execute(
            select(Petition)
            .where(Petition.dom_id == dom_user.id)
            .order_by(desc(Petition.created_at))
        )
    ).scalars().all()

    return [
        PetitionSummary(
            petition_id=item.id,
            status=item.status.value,
            package=item.package_name,
            reason=item.reason,
            created_at=item.created_at,
            approved_minutes=item.approved_minutes,
        )
        for item in petitions
    ]
