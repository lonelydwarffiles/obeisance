from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import Device, LeaseTier, Transaction, TransactionStatus, Wallet

router = APIRouter(tags=["billing"])

CENT_PRECISION = Decimal("0.01")


class CryptoPaymentWebhookPayload(BaseModel):
    device_id: UUID
    amount_paid: Decimal
    external_tx_hash: str
    paid_by_id: UUID | None = None


class CryptoPaymentWebhookResponse(BaseModel):
    transaction_id: UUID
    status: str
    lease_expires_at: datetime


def normalize_amount(value: Decimal) -> Decimal:
    return value.quantize(CENT_PRECISION, rounding=ROUND_HALF_UP)


@router.post(
    "/webhooks/crypto-payment",
    response_model=CryptoPaymentWebhookResponse,
    status_code=status.HTTP_201_CREATED,
)
async def process_crypto_payment(
    payload: CryptoPaymentWebhookPayload,
    db: AsyncSession = Depends(get_db),
) -> CryptoPaymentWebhookResponse:
    existing_tx_result = await db.execute(
        select(Transaction).where(Transaction.external_tx_hash == payload.external_tx_hash)
    )
    existing_tx = existing_tx_result.scalar_one_or_none()
    if existing_tx is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Payment already processed")

    device_result = await db.execute(select(Device).where(Device.id == payload.device_id))
    device = device_result.scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    if device.leased_to_id is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Device is not leased to a Domme")

    lease_tier_result = await db.execute(
        select(LeaseTier).where(
            LeaseTier.domme_id == device.leased_to_id,
            LeaseTier.is_active.is_(True),
        )
    )
    lease_tier = lease_tier_result.scalar_one_or_none()
    if lease_tier is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Active lease tier not found")

    amount_paid = normalize_amount(payload.amount_paid)
    central_cut = normalize_amount(Decimal(str(lease_tier.base_central_fee)))
    domme_cut = normalize_amount(Decimal(str(lease_tier.domme_markup)))
    expected_total = normalize_amount(central_cut + domme_cut)

    if amount_paid != expected_total:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Payment amount does not match lease tier")

    wallet_result = await db.execute(select(Wallet).where(Wallet.user_id == device.leased_to_id))
    wallet = wallet_result.scalar_one_or_none()
    if wallet is None:
        wallet = Wallet(user_id=device.leased_to_id, balance_usdc=0)
        db.add(wallet)

    wallet.balance_usdc = normalize_amount(Decimal(str(wallet.balance_usdc or 0)) + domme_cut)

    now = datetime.now(timezone.utc)
    current_expiry = device.lease_expires_at
    if current_expiry is not None and current_expiry.tzinfo is None:
        current_expiry = current_expiry.replace(tzinfo=timezone.utc)
    lease_start = current_expiry if current_expiry is not None and current_expiry > now else now
    device.lease_expires_at = lease_start + timedelta(days=30)

    transaction = Transaction(
        device_id=device.id,
        paid_by_id=payload.paid_by_id,
        amount_total=amount_paid,
        central_cut=central_cut,
        domme_cut=domme_cut,
        status=TransactionStatus.completed,
        external_tx_hash=payload.external_tx_hash,
    )
    db.add(transaction)

    await db.commit()
    await db.refresh(transaction)

    return CryptoPaymentWebhookResponse(
        transaction_id=transaction.id,
        status=transaction.status.value,
        lease_expires_at=device.lease_expires_at,
    )
