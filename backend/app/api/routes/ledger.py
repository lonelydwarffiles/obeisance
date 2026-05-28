from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.services.ledger import LedgerService

router = APIRouter(tags=["ledger"])


class InvoiceRequest(BaseModel):
    domme_id: UUID
    device_id: UUID


class InvoiceResponse(BaseModel):
    invoice_id: UUID
    amount_central: Decimal
    amount_domme: Decimal
    amount_total: Decimal


class PaymentRequest(BaseModel):
    invoice_id: UUID
    tx_hash: str


class PaymentResponse(BaseModel):
    invoice_id: UUID
    status: str
    tx_hash: str | None


@router.post(
    "/ledger/invoice",
    response_model=InvoiceResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_invoice(
    payload: InvoiceRequest,
    db: AsyncSession = Depends(get_db),
) -> InvoiceResponse:
    split = await LedgerService.calculate_invoice(
        domme_id=payload.domme_id,
        device_id=payload.device_id,
        db=db,
    )
    return InvoiceResponse(
        invoice_id=split.invoice_id,
        amount_central=split.amount_central,
        amount_domme=split.amount_domme,
        amount_total=split.amount_total,
    )


@router.post(
    "/ledger/pay",
    response_model=PaymentResponse,
    status_code=status.HTTP_200_OK,
)
async def pay_invoice(
    payload: PaymentRequest,
    db: AsyncSession = Depends(get_db),
) -> PaymentResponse:
    invoice = await LedgerService.process_crypto_payment(
        invoice_id=payload.invoice_id,
        tx_hash=payload.tx_hash,
        db=db,
    )
    return PaymentResponse(
        invoice_id=invoice.id,
        status=invoice.status.value,
        tx_hash=invoice.external_tx_hash,
    )
