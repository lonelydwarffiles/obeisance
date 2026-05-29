from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP

from sqlalchemy import func, select

from app.core.config import settings
from app.db.database import AsyncSessionLocal
from app.db.models import BillingCycle, BillingCycleStatus, Device, DeviceStatus, User, UserRole
from app.services.btcpay_client import BTCPayBridge
from app.services.notifications import notify_dom_billing_due

CENT = Decimal("0.01")


def _normalize(value: Decimal) -> Decimal:
    return value.quantize(CENT, rounding=ROUND_HALF_UP)


async def run_monthly_billing_cycle() -> None:
    """Daily billing sweep: issue BTCPay invoices for Doms due today."""
    now = datetime.now(timezone.utc)
    today = now.date()
    base_fee = _normalize(Decimal(str(settings.base_platform_fee)))

    async with AsyncSessionLocal() as db:
        doms = (
            await db.execute(
                select(User).where(
                    User.role == UserRole.domme,
                    User.billing_renewal_date.is_not(None),
                )
            )
        ).scalars().all()

        bridge = BTCPayBridge()

        for dom in doms:
            renewal = dom.billing_renewal_date
            if renewal is None:
                continue

            renewal_utc = renewal.astimezone(timezone.utc) if renewal.tzinfo else renewal.replace(tzinfo=timezone.utc)
            if renewal_utc.date() != today:
                continue

            already_exists = (
                await db.execute(
                    select(BillingCycle).where(
                        BillingCycle.dom_id == dom.id,
                        BillingCycle.cycle_start == renewal_utc,
                    )
                )
            ).scalar_one_or_none()
            if already_exists is not None:
                continue

            active_devices_count = int(
                (
                    await db.execute(
                        select(func.count(Device.id)).where(
                            Device.leased_to_id == dom.id,
                            Device.status.in_([DeviceStatus.leased, DeviceStatus.lease_pending]),
                        )
                    )
                ).scalar_one()
                or 0
            )

            total_owed = _normalize(base_fee * Decimal(active_devices_count))
            cycle_end = renewal_utc + timedelta(days=30)

            cycle = BillingCycle(
                dom_id=dom.id,
                cycle_start=renewal_utc,
                cycle_end=cycle_end,
                active_devices_count=active_devices_count,
                total_owed=float(total_owed),
                status=BillingCycleStatus.pending,
            )
            db.add(cycle)
            await db.flush()

            if total_owed <= Decimal("0"):
                cycle.status = BillingCycleStatus.paid
                dom.billing_renewal_date = cycle_end
                continue

            invoice = await bridge.create_store_invoice(
                amount=total_owed,
                item_desc=f"Obeisance infrastructure fee for {dom.username}",
                metadata={
                    "billing_cycle_id": str(cycle.id),
                    "dom_id": str(dom.id),
                },
            )

            cycle.btcpay_invoice_id = invoice.invoice_id
            await notify_dom_billing_due(dom=dom, cycle=cycle)

        await db.commit()
