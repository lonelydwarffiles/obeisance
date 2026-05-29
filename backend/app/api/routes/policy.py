from __future__ import annotations

from datetime import time
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user, require_domme
from app.db.database import get_db
from app.db.models import Device, DevicePolicyProfile, User, UserRole
from app.services.audit import record_audit_event

router = APIRouter(prefix="/policy", tags=["policy"])


class GeofencePolicy(BaseModel):
    latitude: float | None = None
    longitude: float | None = None
    radius_meters: float | None = None
    restricted_packages: list[str] = Field(default_factory=list)


class SleepPolicy(BaseModel):
    start_time: str | None = None  # HH:MM
    end_time: str | None = None  # HH:MM
    non_essential_packages: list[str] = Field(default_factory=list)


class DevicePolicyResponse(BaseModel):
    device_id: UUID
    geofence: GeofencePolicy
    sleep: SleepPolicy


class UpdateDevicePolicyRequest(BaseModel):
    device_id: UUID
    geofence: GeofencePolicy
    sleep: SleepPolicy


def _parse_hhmm(value: str | None) -> time | None:
    if value is None:
        return None
    parts = value.split(":")
    if len(parts) != 2:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid HH:MM time format")
    hour = int(parts[0])
    minute = int(parts[1])
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid HH:MM time value")
    return time(hour=hour, minute=minute)


def _format_time(value: time | None) -> str | None:
    if value is None:
        return None
    return f"{value.hour:02d}:{value.minute:02d}"


@router.get("/device/{device_id}", response_model=DevicePolicyResponse, status_code=status.HTTP_200_OK)
async def get_device_policy(
    device_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> DevicePolicyResponse:
    device = (await db.execute(select(Device).where(Device.id == device_id))).scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")

    # Dom can only fetch their own leased device. Superadmin can fetch all.
    if current_user.role == UserRole.domme and device.leased_to_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Device does not belong to current Dom")

    profile = (
        await db.execute(select(DevicePolicyProfile).where(DevicePolicyProfile.device_id == device_id))
    ).scalar_one_or_none()

    if profile is None:
        return DevicePolicyResponse(
            device_id=device_id,
            geofence=GeofencePolicy(),
            sleep=SleepPolicy(),
        )

    return DevicePolicyResponse(
        device_id=device_id,
        geofence=GeofencePolicy(
            latitude=profile.geofence_latitude,
            longitude=profile.geofence_longitude,
            radius_meters=profile.geofence_radius_meters,
            restricted_packages=profile.restricted_packages,
        ),
        sleep=SleepPolicy(
            start_time=_format_time(profile.sleep_start_time),
            end_time=_format_time(profile.sleep_end_time),
            non_essential_packages=profile.sleep_non_essential_packages,
        ),
    )


@router.put("/device", response_model=DevicePolicyResponse, status_code=status.HTTP_200_OK)
async def update_device_policy(
    payload: UpdateDevicePolicyRequest,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> DevicePolicyResponse:
    device = (await db.execute(select(Device).where(Device.id == payload.device_id))).scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    if device.leased_to_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Device does not belong to current Dom")

    profile = (
        await db.execute(select(DevicePolicyProfile).where(DevicePolicyProfile.device_id == payload.device_id))
    ).scalar_one_or_none()
    if profile is None:
        profile = DevicePolicyProfile(device_id=payload.device_id)
        db.add(profile)

    profile.geofence_latitude = payload.geofence.latitude
    profile.geofence_longitude = payload.geofence.longitude
    profile.geofence_radius_meters = payload.geofence.radius_meters
    profile.restricted_packages = payload.geofence.restricted_packages
    profile.sleep_start_time = _parse_hhmm(payload.sleep.start_time)
    profile.sleep_end_time = _parse_hhmm(payload.sleep.end_time)
    profile.sleep_non_essential_packages = payload.sleep.non_essential_packages

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=payload.device_id,
        action="policy_updated",
        target_type="device_policy",
        target_id=str(payload.device_id),
        metadata={
            "geofence": payload.geofence.model_dump(),
            "sleep": payload.sleep.model_dump(),
        },
    )

    await db.commit()

    return DevicePolicyResponse(
        device_id=payload.device_id,
        geofence=payload.geofence,
        sleep=payload.sleep,
    )
