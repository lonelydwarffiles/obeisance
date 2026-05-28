from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import CandidateProfile, Device
from app.schemas.candidate import CandidateProfileResponse, CandidatePublishRequest

router = APIRouter(tags=["candidate"])


@router.post("/candidate/publish", response_model=CandidateProfileResponse, status_code=status.HTTP_200_OK)
async def publish_candidate_profile(
    payload: CandidatePublishRequest,
    db: AsyncSession = Depends(get_db),
    x_device_id: UUID | None = Header(default=None),
) -> CandidateProfileResponse:
    if x_device_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing device id")

    device_result = await db.execute(select(Device).where(Device.id == x_device_id))
    if device_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")

    result = await db.execute(select(CandidateProfile).where(CandidateProfile.device_id == x_device_id))
    profile = result.scalar_one_or_none()
    if profile is None:
        profile = CandidateProfile(
            device_id=x_device_id,
            anonymized_interests=payload.anonymized_interests,
            is_published=True,
        )
        db.add(profile)
    else:
        profile.anonymized_interests = payload.anonymized_interests
        profile.is_published = True
        profile.updated_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(profile)
    return CandidateProfileResponse(
        id=profile.id,
        device_id=profile.device_id,
        anonymized_interests=profile.anonymized_interests,
        readiness_score=profile.readiness_score,
        is_published=profile.is_published,
        updated_at=profile.updated_at,
    )


@router.get("/candidate/messages")
async def list_candidate_messages(
    x_device_id: UUID | None = Header(default=None),
) -> list[dict]:
    if x_device_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing device id")
    # TODO: implement connection request messaging system
    return []
