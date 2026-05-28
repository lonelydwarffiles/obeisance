from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Device


class MDMBridge:
    @staticmethod
    async def unlockDevice(device_id: UUID, db: AsyncSession) -> bool:  # noqa: N802 - required external name
        device = (await db.execute(select(Device).where(Device.id == device_id))).scalar_one_or_none()
        if device is None:
            return False
        return True

