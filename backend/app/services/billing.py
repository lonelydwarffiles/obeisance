import secrets
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Device, Invoice, InvoiceStatus, InviteLink, LeaseTier, Tenant
from app.services.btcpay_client import BTCPayBridge

CENT_PRECISION = Decimal("0.01")


def _normalize_amount(value: Decimal) -> Decimal:
    return value.quantize(CENT_PRECISION, rounding=ROUND_HALF_UP)


@dataclass(slots=True)
class GrowthStats:
    active_subs: int
    total_slots: int


@dataclass(slots=True)
class SubInvoiceResult:
    invoice_id: UUID
    btcpay_invoice_id: str
    checkout_url: str | None
    amount_total: Decimal
    platform_fee: Decimal
    dom_markup: Decimal


def _generate_slug(length: int = 10) -> str:
    return secrets.token_urlsafe(length)[:length].lower()


async def create_invite_link(creator_id: UUID, db: AsyncSession) -> InviteLink:
    slug = _generate_slug()
    while (await db.execute(select(InviteLink).where(InviteLink.slug == slug))).scalar_one_or_none() is not None:
        slug = _generate_slug()

    invite = InviteLink(creator_id=creator_id, slug=slug, is_active=True)
    db.add(invite)
    await db.commit()
    await db.refresh(invite)
    return invite


async def process_signup(invite_slug: str, db: AsyncSession) -> InviteLink:
    invite_result = await db.execute(
        select(InviteLink).where(
            InviteLink.slug == invite_slug,
            InviteLink.is_active.is_(True),
        )
    )
    invite = invite_result.scalar_one_or_none()
    if invite is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or inactive invite link")

    if invite.current_uses >= invite.max_uses:
        invite.is_active = False
        await db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invite link is exhausted")

    invite.current_uses += 1
    if invite.current_uses >= invite.max_uses:
        invite.is_active = False

    tenant_result = await db.execute(select(Tenant).where(Tenant.owner_id == invite.creator_id))
    tenant = tenant_result.scalar_one_or_none()
    if tenant is None:
        tenant = Tenant(owner_id=invite.creator_id, base_slots=0)
        db.add(tenant)

    tenant.base_slots += 1
    await db.commit()
    await db.refresh(invite)
    return invite


async def get_growth_stats(owner_id: UUID, db: AsyncSession) -> GrowthStats:
    tenant_result = await db.execute(select(Tenant).where(Tenant.owner_id == owner_id))
    tenant = tenant_result.scalar_one_or_none()
    total_slots = tenant.base_slots if tenant is not None else 0

    active_subs_result = await db.execute(
        select(func.count(Device.id)).where(Device.leased_to_id == owner_id)
    )
    active_subs = int(active_subs_result.scalar_one() or 0)

    return GrowthStats(active_subs=active_subs, total_slots=total_slots)


async def generate_sub_invoice(device_id: UUID, db: AsyncSession) -> SubInvoiceResult:
    """Create a unified Central invoice and persist Dom payout split metadata."""
    device = (await db.execute(select(Device).where(Device.id == device_id))).scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")

    domme_id = device.leased_to_id
    if domme_id is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Device is not assigned to a Dom")

    lease_tier = (
        await db.execute(
            select(LeaseTier).where(
                LeaseTier.domme_id == domme_id,
                LeaseTier.is_active.is_(True),
            )
        )
    ).scalar_one_or_none()
    if lease_tier is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active lease tier for this Dom")

    platform_fee = _normalize_amount(Decimal(str(lease_tier.base_central_fee)))
    dom_markup = _normalize_amount(Decimal(str(lease_tier.domme_markup)))
    total_fee = _normalize_amount(platform_fee + dom_markup)

    bridge = BTCPayBridge()
    # Persist first so internal id can be attached to BTCPay metadata for webhook mapping.
    invoice = Invoice(
        payer_id=None,
        receiver_id=domme_id,
        device_id=device_id,
        amount_total=float(total_fee),
        amount_central=float(platform_fee),
        amount_domme=float(dom_markup),
        dom_payout_amount=float(dom_markup),
        status=InvoiceStatus.pending,
    )
    db.add(invoice)
    await db.flush()

    btcpay_invoice = await bridge.create_invoice(
        amount=total_fee,
        domme_wallet_id=str(domme_id),
        sub_device_id=str(device_id),
        internal_invoice_id=str(invoice.id),
    )

    invoice.btcpay_invoice_id = btcpay_invoice.invoice_id
    invoice.btcpay_checkout_url = btcpay_invoice.checkout_link

    await db.commit()
    await db.refresh(invoice)

    return SubInvoiceResult(
        invoice_id=invoice.id,
        btcpay_invoice_id=btcpay_invoice.invoice_id,
        checkout_url=btcpay_invoice.checkout_link,
        amount_total=total_fee,
        platform_fee=platform_fee,
        dom_markup=dom_markup,
    )
