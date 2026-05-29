from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Invoice, InvoiceStatus, Tenant
from app.services.btcpay_client import BTCPayBridge


def _derive_dom_payout_sats(invoice: Invoice, settled_total_sats: int | None) -> int:
    if invoice.dom_payout_sats is not None and invoice.dom_payout_sats > 0:
        return int(invoice.dom_payout_sats)

    if settled_total_sats is None or settled_total_sats <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing settled amount in sats for payout split",
        )

    amount_total = Decimal(str(invoice.amount_total or 0))
    amount_domme = Decimal(str(invoice.dom_payout_amount or invoice.amount_domme or 0))
    if amount_total <= 0 or amount_domme <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid invoice split amounts")

    ratio = amount_domme / amount_total
    sats = (Decimal(str(settled_total_sats)) * ratio).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    computed_sats = int(sats)
    if computed_sats <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Computed payout amount is zero")
    return computed_sats


async def process_lightning_payout(
    invoice_id: UUID,
    db: AsyncSession,
    settled_total_sats: int | None = None,
) -> Invoice:
    invoice = (await db.execute(select(Invoice).where(Invoice.id == invoice_id))).scalar_one_or_none()
    if invoice is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")

    if invoice.status == InvoiceStatus.settled_and_split:
        return invoice

    tenant = (
        await db.execute(select(Tenant).where(Tenant.owner_id == invoice.receiver_id))
    ).scalar_one_or_none()
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tenant profile not found for Dom")

    destination = tenant.lightning_address or tenant.lnurl
    if not destination:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Dom has no lightning payout destination configured",
        )

    payout_sats = _derive_dom_payout_sats(invoice, settled_total_sats)

    bridge = BTCPayBridge()
    payout = await bridge.execute_lightning_payout(destination=destination, amount_sats=payout_sats)

    invoice.dom_payout_sats = payout_sats
    invoice.payout_tx_hash = payout.payment_hash
    invoice.payout_error = None
    invoice.status = InvoiceStatus.settled_and_split

    await db.commit()
    await db.refresh(invoice)
    return invoice
