from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from app.core.config import settings
from app.db.database import AsyncSessionLocal
from app.db.models import BillingCycle, BillingCycleStatus, Device, DeviceStatus, User
from app.services.notifications import send_revoke_authority_command


async def run_billing_enforcement_sweeper() -> None:
    """Daily enforcement sweep for overdue Central invoices."""
    now = datetime.now(timezone.utc)
    overdue_cutoff = now - timedelta(hours=settings.billing_grace_hours)

    async with AsyncSessionLocal() as db:
        overdue_cycles = (
            await db.execute(
                select(BillingCycle).where(
                    BillingCycle.status == BillingCycleStatus.pending,
                    BillingCycle.created_at <= overdue_cutoff,
                )
            )
        ).scalars().all()

        for cycle in overdue_cycles:
            cycle.status = BillingCycleStatus.overdue

            dom = (await db.execute(select(User).where(User.id == cycle.dom_id))).scalar_one_or_none()
            if dom is not None:
                dom.is_active = False

            devices = (
                await db.execute(
                    select(Device).where(
                        Device.leased_to_id == cycle.dom_id,
                        Device.status.in_([DeviceStatus.leased, DeviceStatus.lease_pending]),
                    )
                )
            ).scalars().all()

            for device in devices:
                await send_revoke_authority_command(device.id)

        await db.commit()
