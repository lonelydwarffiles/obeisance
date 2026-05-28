from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Device, TempoMetricEvent, TempoShareCadence, TempoShareSummary, TempoSharingPreference

CADENCE_WINDOWS: dict[TempoShareCadence, timedelta] = {
    TempoShareCadence.daily: timedelta(days=1),
    TempoShareCadence.weekly: timedelta(days=7),
    TempoShareCadence.monthly: timedelta(days=30),
}


@dataclass(slots=True)
class TempoAggregate:
    average_velocity: float
    peak_velocity: float
    sample_count: int
    behavior: str


def _normalize_ts(value: datetime | None, fallback: datetime) -> datetime:
    if value is None:
        return fallback
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _behavior_from_average(average_velocity: float) -> str:
    return "frantic" if average_velocity > 1200 else "steady"


async def get_or_create_preference(device: Device, db: AsyncSession) -> TempoSharingPreference:
    preference_result = await db.execute(
        select(TempoSharingPreference).where(TempoSharingPreference.device_id == device.id)
    )
    preference = preference_result.scalar_one_or_none()
    if preference is None:
        preference = TempoSharingPreference(device_id=device.id)
        db.add(preference)
        await db.flush()
    return preference


async def analyze_tempo(
    device: Device,
    db: AsyncSession,
    *,
    now: datetime | None = None,
    cadence: TempoShareCadence = TempoShareCadence.daily,
) -> TempoAggregate:
    period_end = _normalize_ts(now, datetime.now(timezone.utc))
    period_start = period_end - CADENCE_WINDOWS[cadence]

    events = (
        (
            await db.execute(
                select(TempoMetricEvent.velocity).where(
                    and_(
                        TempoMetricEvent.device_id == device.id,
                        TempoMetricEvent.observed_at >= period_start,
                        TempoMetricEvent.observed_at <= period_end,
                    )
                )
            )
        )
        .scalars()
        .all()
    )
    if not events:
        return TempoAggregate(average_velocity=0.0, peak_velocity=0.0, sample_count=0, behavior="steady")

    peak_velocity = max(float(entry) for entry in events)
    average_velocity = sum(float(entry) for entry in events) / len(events)
    return TempoAggregate(
        average_velocity=average_velocity,
        peak_velocity=peak_velocity,
        sample_count=len(events),
        behavior=_behavior_from_average(average_velocity),
    )


async def record_tempo_events(
    device: Device,
    events: list[tuple[float, datetime | None]],
    db: AsyncSession,
    *,
    now: datetime | None = None,
) -> int:
    current = _normalize_ts(now, datetime.now(timezone.utc))
    persisted = 0
    for velocity, observed_at in events:
        entry = TempoMetricEvent(
            device_id=device.id,
            velocity=max(0.0, velocity),
            observed_at=_normalize_ts(observed_at, current),
        )
        db.add(entry)
        persisted += 1
    return persisted


async def process_due_tempo_summaries(db: AsyncSession, *, now: datetime | None = None) -> int:
    period_end = _normalize_ts(now, datetime.now(timezone.utc))
    preferences = (
        (
            await db.execute(
                select(TempoSharingPreference, Device)
                .join(Device, Device.id == TempoSharingPreference.device_id)
                .where(
                    TempoSharingPreference.sharing_enabled.is_(True),
                    TempoSharingPreference.sharing_paused.is_(False),
                    Device.leased_to_id.is_not(None),
                )
            )
        )
        .all()
    )

    created = 0
    for preference, device in preferences:
        cadence_window = CADENCE_WINDOWS[preference.cadence]
        if preference.consented_at is None:
            continue

        consented_at = _normalize_ts(preference.consented_at, period_end)
        last_shared_at = _normalize_ts(preference.last_shared_at, consented_at)
        if period_end < last_shared_at + cadence_window:
            continue

        period_start = period_end - cadence_window
        aggregate = await analyze_tempo(device, db, now=period_end, cadence=preference.cadence)
        summary = TempoShareSummary(
            device_id=device.id,
            domme_id=device.leased_to_id,
            cadence=preference.cadence,
            period_start=period_start,
            period_end=period_end,
            average_velocity=aggregate.average_velocity,
            peak_velocity=aggregate.peak_velocity,
            sample_count=aggregate.sample_count,
            delivery_status="delivered",
            delivered_at=period_end,
        )
        db.add(summary)
        preference.last_shared_at = period_end
        preference.updated_at = period_end
        created += 1

    return created
