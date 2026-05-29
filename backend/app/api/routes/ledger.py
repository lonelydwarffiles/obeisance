from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import BillingDisplayMode, DommeSettings, Invoice
from app.services.billing import generate_sub_invoice
from app.services.ledger import LedgerService

router = APIRouter(tags=["ledger"])


class InvoiceRequest(BaseModel):
    domme_id: UUID
    device_id: UUID


class InvoiceResponse(BaseModel):
    invoice_id: UUID
    btcpay_invoice_id: str | None = None
    checkout_url: str | None = None
    amount_total: Decimal
    base_platform_fee: Decimal | None = None
    domme_markup: Decimal | None = None


class PaymentRequest(BaseModel):
    invoice_id: UUID
    tx_hash: str


class PaymentResponse(BaseModel):
    invoice_id: UUID
    status: str
    tx_hash: str | None


class InvoiceStatusResponse(BaseModel):
    invoice_id: UUID
    status: str
    checkout_url: str | None = None


class BillingSettingsResponse(BaseModel):
    domme_id: UUID
    billing_display_mode: BillingDisplayMode


class BillingSettingsRequest(BaseModel):
    domme_id: UUID
    billing_display_mode: BillingDisplayMode


@router.post(
    "/ledger/invoice",
    response_model=InvoiceResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_invoice(
    payload: InvoiceRequest,
    db: AsyncSession = Depends(get_db),
) -> InvoiceResponse:
    split = await generate_sub_invoice(device_id=payload.device_id, db=db)
    return InvoiceResponse(
        invoice_id=split.invoice_id,
        btcpay_invoice_id=split.btcpay_invoice_id,
        checkout_url=split.checkout_url,
        amount_total=split.amount_total,
        base_platform_fee=split.platform_fee,
        domme_markup=split.dom_markup,
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


@router.get(
    "/ledger/invoice/{invoice_id}",
    response_model=InvoiceStatusResponse,
    status_code=status.HTTP_200_OK,
)
async def get_invoice_status(
    invoice_id: UUID,
    db: AsyncSession = Depends(get_db),
) -> InvoiceStatusResponse:
    invoice = (await db.execute(select(Invoice).where(Invoice.id == invoice_id))).scalar_one_or_none()
    if invoice is None:
        return InvoiceStatusResponse(invoice_id=invoice_id, status="missing", checkout_url=None)

    return InvoiceStatusResponse(
        invoice_id=invoice.id,
        status=invoice.status.value,
        checkout_url=invoice.btcpay_checkout_url,
    )


@router.get(
    "/ledger/settings/{domme_id}",
    response_model=BillingSettingsResponse,
    status_code=status.HTTP_200_OK,
)
async def get_billing_settings(
    domme_id: UUID,
    db: AsyncSession = Depends(get_db),
) -> BillingSettingsResponse:
    result = await db.execute(select(DommeSettings).where(DommeSettings.domme_id == domme_id))
    settings = result.scalar_one_or_none()
    mode = settings.billing_display_mode if settings is not None else BillingDisplayMode.unified
    return BillingSettingsResponse(domme_id=domme_id, billing_display_mode=mode)


@router.put(
    "/ledger/settings",
    response_model=BillingSettingsResponse,
    status_code=status.HTTP_200_OK,
)
async def update_billing_settings(
    payload: BillingSettingsRequest,
    db: AsyncSession = Depends(get_db),
) -> BillingSettingsResponse:
    result = await db.execute(select(DommeSettings).where(DommeSettings.domme_id == payload.domme_id))
    settings = result.scalar_one_or_none()
    if settings is None:
        settings = DommeSettings(domme_id=payload.domme_id, billing_display_mode=payload.billing_display_mode)
        db.add(settings)
    else:
        settings.billing_display_mode = payload.billing_display_mode
    await db.commit()
    await db.refresh(settings)
    return BillingSettingsResponse(domme_id=settings.domme_id, billing_display_mode=settings.billing_display_mode)
