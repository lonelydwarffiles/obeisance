from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import Device, DeviceStatus, User, UserRole

router = APIRouter(tags=["device"])


class DeviceInitRequest(BaseModel):
    hardware_uuid: str


class DeviceInitResponse(BaseModel):
    hardware_uuid: str
    status: str


@router.post("/init", response_model=DeviceInitResponse, status_code=status.HTTP_200_OK)
async def initialize_device(payload: DeviceInitRequest, db: AsyncSession = Depends(get_db)) -> DeviceInitResponse:
    owner_result = await db.execute(select(User).where(User.role == UserRole.superadmin))
    superadmin = owner_result.scalar_one_or_none()
    if superadmin is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Superadmin user not found")

    device_result = await db.execute(select(Device).where(Device.hardware_uuid == payload.hardware_uuid))
    device = device_result.scalar_one_or_none()

    if device is None:
        device = Device(
            central_owner_id=superadmin.id,
            leased_to_id=None,
            hardware_uuid=payload.hardware_uuid,
            status=DeviceStatus.unclaimed_pool,
            last_seen=datetime.now(timezone.utc),
        )
        db.add(device)
    else:
        device.last_seen = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(device)

    return DeviceInitResponse(hardware_uuid=device.hardware_uuid, status=device.status.value)
