import hashlib
import hmac
import json
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.database import get_db
from app.db.models import Device, DeviceStatus, Invoice, InvoiceStatus
from app.services.ledger import LedgerService
from app.services.mdm_bridge import MDMBridge
from app.tasks.payout_handler import process_lightning_payout

router = APIRouter(tags=["webhooks"])


class WebhookAck(BaseModel):
    received: bool
    event: str
    invoice_id: UUID | None = None


def _verify_signature(raw_body: bytes, sig_header: str | None) -> bool:
    secret = settings.btcpay_webhook_secret
    if not secret or not sig_header:
        return False
    expected = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    received = sig_header.strip()
    if received.startswith("sha256="):
        received = received[7:]
    return hmac.compare_digest(expected, received)


def _extract_event_type(payload: dict) -> str:
    return str(payload.get("type") or payload.get("name") or payload.get("eventCode") or "")


def _extract_btcpay_invoice_id(payload: dict) -> str:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    return str(payload.get("invoiceId") or data.get("id") or "")


def _extract_internal_invoice_id(payload: dict) -> str:
    metadata: dict = {}
    if isinstance(payload.get("metadata"), dict):
        metadata = payload["metadata"]
    elif isinstance(payload.get("data"), dict) and isinstance(payload["data"].get("metadata"), dict):
        metadata = payload["data"]["metadata"]
    return str(
        metadata.get("internal_invoice_id")
        or metadata.get("invoice_id")
        or payload.get("orderId")
        or ""
    )


def _extract_settled_sats(payload: dict) -> int | None:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}

    candidates = [
        data.get("amount"),
        data.get("value"),
        data.get("paidAmount"),
    ]

    payment = data.get("payment") if isinstance(data.get("payment"), dict) else None
    if payment is not None:
        candidates.extend([payment.get("value"), payment.get("amount")])

    for candidate in candidates:
        try:
            if candidate is None:
                continue
            sats = int(str(candidate))
            if sats > 0:
                return sats
        except (TypeError, ValueError):
            continue
    return None


@router.post("/webhooks/btcpay", response_model=WebhookAck, status_code=status.HTTP_200_OK)
async def btcpay_webhook(
    request: Request,
    db: AsyncSession = Depends(get_db),
    btcpay_sig: str | None = Header(default=None, alias="X-BTCPAY-SIG"),
) -> WebhookAck:
    raw_body = await request.body()
    if not _verify_signature(raw_body, btcpay_sig):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid BTCPay signature")

    payload = json.loads(raw_body.decode("utf-8") or "{}")
    event_type = _extract_event_type(payload)
    if event_type not in {"InvoicePaymentSettled", "InvoiceSettled"}:
        return WebhookAck(received=True, event=event_type or "ignored")

    internal_invoice_id = _extract_internal_invoice_id(payload)
    if not internal_invoice_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing internal invoice identifier")

    try:
        invoice_uuid = UUID(internal_invoice_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid internal invoice identifier") from exc

    invoice = (await db.execute(select(Invoice).where(Invoice.id == invoice_uuid))).scalar_one_or_none()
    if invoice is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")

    btcpay_invoice_id = _extract_btcpay_invoice_id(payload) or f"btcpay:{invoice_uuid}"

    updated_invoice = await LedgerService.process_crypto_payment(
        invoice_id=invoice.id,
        tx_hash=btcpay_invoice_id,
        db=db,
    )

    settled_sats = _extract_settled_sats(payload)
    try:
        updated_invoice = await process_lightning_payout(
            invoice_id=invoice.id,
            db=db,
            settled_total_sats=settled_sats,
        )
    except HTTPException as exc:
        invoice.payout_error = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
        invoice.status = InvoiceStatus.payout_failed
        await db.commit()
        raise

    device = (await db.execute(select(Device).where(Device.id == invoice.device_id))).scalar_one_or_none()
    if device is not None and device.status == DeviceStatus.lease_pending and updated_invoice.status.value == "settled_and_split":
        unlocked = await MDMBridge.unlockDevice(device.id, db)
        if unlocked:
            device.status = DeviceStatus.leased
            await db.commit()

    return WebhookAck(
        received=True,
        event=event_type,
        invoice_id=invoice.id,
    )

