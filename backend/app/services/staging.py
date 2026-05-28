from dataclasses import dataclass, field
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import DailyPrepTask, Device


@dataclass(slots=True)
class StagingPayload:
    mode: str  # "staging" | "assigned"
    branding_name: str
    tasks: list[DailyPrepTask] = field(default_factory=list)


class StagingService:
    @staticmethod
    async def get_dashboard_payload(device_id: UUID, db: AsyncSession) -> StagingPayload:
        device = (
            await db.execute(select(Device).where(Device.id == device_id))
        ).scalar_one_or_none()
        if device is None:
            raise ValueError("Device not found")

        is_staging = device.leased_to_id is None

        if not is_staging:
            return StagingPayload(mode="assigned", branding_name="Obeisance", tasks=[])

        prep_tasks = list(
            (
                await db.execute(
                    select(DailyPrepTask)
                    .where(DailyPrepTask.is_active.is_(True))
                    .order_by(DailyPrepTask.sort_order.asc())
                )
            ).scalars().all()
        )

        return StagingPayload(
            mode="staging",
            branding_name="Obeisance Staging",
            tasks=prep_tasks,
        )
