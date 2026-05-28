from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Device, Invoice, InvoiceStatus, LeaseTier, Transaction, TransactionStatus, Wallet

CENT_PRECISION = Decimal("0.01")


def _normalize(value: Decimal) -> Decimal:
    return value.quantize(CENT_PRECISION, rounding=ROUND_HALF_UP)


@dataclass(slots=True)
class InvoiceSplit:
    invoice_id: UUID
    amount_central: Decimal
    amount_domme: Decimal
    amount_total: Decimal


class LedgerService:
    @staticmethod
    async def calculate_invoice(domme_id: UUID, device_id: UUID, db: AsyncSession) -> InvoiceSplit:
        """Create a pending Invoice from the active LeaseTier for a Domme and return the split."""
        device_result = await db.execute(select(Device).where(Device.id == device_id))
        device = device_result.scalar_one_or_none()
        if device is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")

        lease_tier_result = await db.execute(
            select(LeaseTier).where(
                LeaseTier.domme_id == domme_id,
                LeaseTier.is_active.is_(True),
            )
        )
        lease_tier = lease_tier_result.scalar_one_or_none()
        if lease_tier is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active lease tier for this Domme")

        amount_central = _normalize(Decimal(str(lease_tier.base_central_fee)))
        amount_domme = _normalize(Decimal(str(lease_tier.domme_markup)))
        amount_total = _normalize(amount_central + amount_domme)

        invoice = Invoice(
            payer_id=None,
            receiver_id=domme_id,
            device_id=device_id,
            amount_total=float(amount_total),
            amount_central=float(amount_central),
            amount_domme=float(amount_domme),
            status=InvoiceStatus.pending,
        )
        db.add(invoice)
        await db.commit()
        await db.refresh(invoice)

        return InvoiceSplit(
            invoice_id=invoice.id,
            amount_central=amount_central,
            amount_domme=amount_domme,
            amount_total=amount_total,
        )

    @staticmethod
    async def process_crypto_payment(invoice_id: UUID, tx_hash: str, db: AsyncSession) -> Invoice:
        """Validate a blockchain transaction hash and mark the Invoice as paid."""
        invoice_result = await db.execute(select(Invoice).where(Invoice.id == invoice_id))
        invoice = invoice_result.scalar_one_or_none()
        if invoice is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")

        if invoice.status == InvoiceStatus.paid:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Invoice already paid")

        existing_tx_result = await db.execute(
            select(Invoice).where(
                Invoice.external_tx_hash == tx_hash,
                Invoice.id != invoice_id,
            )
        )
        if existing_tx_result.scalar_one_or_none() is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Transaction hash already used")

        invoice.external_tx_hash = tx_hash
        invoice.status = InvoiceStatus.paid

        wallet_result = await db.execute(select(Wallet).where(Wallet.user_id == invoice.receiver_id))
        wallet = wallet_result.scalar_one_or_none()
        if wallet is None:
            wallet = Wallet(user_id=invoice.receiver_id, balance_usdc=0)
            db.add(wallet)

        domme_cut = _normalize(Decimal(str(invoice.amount_domme)))
        wallet.balance_usdc = float(
            _normalize(Decimal(str(wallet.balance_usdc or 0)) + domme_cut)
        )

        transaction = Transaction(
            device_id=invoice.device_id,
            paid_by_id=invoice.payer_id,
            amount_total=invoice.amount_total,
            central_cut=invoice.amount_central,
            domme_cut=invoice.amount_domme,
            status=TransactionStatus.completed,
            external_tx_hash=tx_hash,
        )
        db.add(transaction)

        await db.commit()
        await db.refresh(invoice)
        return invoice
