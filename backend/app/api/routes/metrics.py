from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import AsyncSessionLocal, get_db
from app.db.models import Device, TempoShareCadence, TempoShareSummary
from app.services.metrics import get_or_create_preference, process_due_tempo_summaries, record_tempo_events

router = APIRouter(prefix="/metrics/tempo", tags=["metrics"])


class TempoEventPayload(BaseModel):
    velocity: float = Field(ge=0)
    observed_at: datetime | None = None


class TempoEventsRequest(BaseModel):
    events: list[TempoEventPayload] = Field(default_factory=list)


class TempoEventsResponse(BaseModel):
    persisted_events: int


class TempoSettingsRequest(BaseModel):
    sharing_enabled: bool
    cadence: TempoShareCadence
    sharing_paused: bool = False
    consent_acknowledged: bool = False


class TempoSettingsResponse(BaseModel):
    sharing_enabled: bool
    cadence: TempoShareCadence
    sharing_paused: bool
    consented_at: datetime | None
    revoked_at: datetime | None
    updated_at: datetime


class TempoHistoryEntry(BaseModel):
    id: UUID
    cadence: TempoShareCadence
    period_start: datetime
    period_end: datetime
    average_velocity: float
    peak_velocity: float
    sample_count: int
    delivery_status: str
    delivered_at: datetime


class TempoDispatchResponse(BaseModel):
    generated_summaries: int


async def _device_from_header(hardware_uuid: str | None, db: AsyncSession) -> Device:
    if hardware_uuid is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing hardware uuid")
    device_result = await db.execute(select(Device).where(Device.hardware_uuid == hardware_uuid))
    device = device_result.scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    return device


@router.post("/events", response_model=TempoEventsResponse, status_code=status.HTTP_202_ACCEPTED)
async def ingest_tempo_events(
    payload: TempoEventsRequest,
    db: AsyncSession = Depends(get_db),
    x_hardware_uuid: str | None = Header(default=None),
) -> TempoEventsResponse:
    device = await _device_from_header(x_hardware_uuid, db)
    persisted_events = await record_tempo_events(
        device,
        [(entry.velocity, entry.observed_at) for entry in payload.events],
        db,
    )
    await db.commit()
    return TempoEventsResponse(persisted_events=persisted_events)


@router.get("/settings", response_model=TempoSettingsResponse)
async def get_tempo_settings(
    db: AsyncSession = Depends(get_db),
    x_hardware_uuid: str | None = Header(default=None),
) -> TempoSettingsResponse:
    device = await _device_from_header(x_hardware_uuid, db)
    preference = await get_or_create_preference(device, db)
    await db.commit()
    return TempoSettingsResponse(
        sharing_enabled=preference.sharing_enabled,
        cadence=preference.cadence,
        sharing_paused=preference.sharing_paused,
        consented_at=preference.consented_at,
        revoked_at=preference.revoked_at,
        updated_at=preference.updated_at,
    )


@router.put("/settings", response_model=TempoSettingsResponse)
async def update_tempo_settings(
    payload: TempoSettingsRequest,
    db: AsyncSession = Depends(get_db),
    x_hardware_uuid: str | None = Header(default=None),
) -> TempoSettingsResponse:
    device = await _device_from_header(x_hardware_uuid, db)
    preference = await get_or_create_preference(device, db)
    now = datetime.now(timezone.utc)

    if payload.sharing_enabled and not payload.consent_acknowledged and preference.consented_at is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Consent acknowledgement is required to enable sharing",
        )

    preference.sharing_enabled = payload.sharing_enabled
    preference.cadence = payload.cadence
    preference.sharing_paused = payload.sharing_paused if payload.sharing_enabled else False
    preference.updated_at = now
    if payload.sharing_enabled:
        preference.consented_at = preference.consented_at or now
        preference.revoked_at = None
    else:
        preference.revoked_at = now
        preference.last_shared_at = None

    await db.commit()
    await db.refresh(preference)
    return TempoSettingsResponse(
        sharing_enabled=preference.sharing_enabled,
        cadence=preference.cadence,
        sharing_paused=preference.sharing_paused,
        consented_at=preference.consented_at,
        revoked_at=preference.revoked_at,
        updated_at=preference.updated_at,
    )


@router.get("/history", response_model=list[TempoHistoryEntry])
async def get_sharing_history(
    db: AsyncSession = Depends(get_db),
    x_hardware_uuid: str | None = Header(default=None),
) -> list[TempoHistoryEntry]:
    device = await _device_from_header(x_hardware_uuid, db)
    result = await db.execute(
        select(TempoShareSummary)
        .where(TempoShareSummary.device_id == device.id)
        .order_by(desc(TempoShareSummary.delivered_at))
        .limit(30)
    )
    entries = result.scalars().all()
    return [
        TempoHistoryEntry(
            id=entry.id,
            cadence=entry.cadence,
            period_start=entry.period_start,
            period_end=entry.period_end,
            average_velocity=entry.average_velocity,
            peak_velocity=entry.peak_velocity,
            sample_count=entry.sample_count,
            delivery_status=entry.delivery_status,
            delivered_at=entry.delivered_at,
        )
        for entry in entries
    ]


@router.get("/domme/summaries", response_model=list[TempoHistoryEntry])
async def get_domme_summaries(
    cadence: TempoShareCadence | None = None,
    db: AsyncSession = Depends(get_db),
    x_mock_domme_user_id: UUID | None = Header(default=None),
) -> list[TempoHistoryEntry]:
    if x_mock_domme_user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing mock Domme user id")

    query = select(TempoShareSummary).where(TempoShareSummary.domme_id == x_mock_domme_user_id)
    if cadence is not None:
        query = query.where(TempoShareSummary.cadence == cadence)

    entries = (
        (await db.execute(query.order_by(desc(TempoShareSummary.delivered_at)).limit(60))).scalars().all()
    )
    return [
        TempoHistoryEntry(
            id=entry.id,
            cadence=entry.cadence,
            period_start=entry.period_start,
            period_end=entry.period_end,
            average_velocity=entry.average_velocity,
            peak_velocity=entry.peak_velocity,
            sample_count=entry.sample_count,
            delivery_status=entry.delivery_status,
            delivered_at=entry.delivered_at,
        )
        for entry in entries
    ]


@router.post("/dispatch", response_model=TempoDispatchResponse)
async def dispatch_due_summaries() -> TempoDispatchResponse:
    async with AsyncSessionLocal() as session:
        generated = await process_due_tempo_summaries(session)
        await session.commit()
    return TempoDispatchResponse(generated_summaries=generated)
