from __future__ import annotations

import asyncio
from dataclasses import dataclass
from decimal import Decimal

from fastapi import HTTPException, status

from app.core.config import settings

try:
    from btcpay import BTCPayClient
except Exception:  # pragma: no cover - import availability differs by environment
    BTCPayClient = None  # type: ignore[assignment]


@dataclass(slots=True)
class BTCPayInvoiceResult:
    invoice_id: str
    checkout_link: str | None
    bitcoin_uri: str | None


class BTCPayBridge:
    def __init__(self) -> None:
        if BTCPayClient is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="btcpay-python is not installed",
            )
        if not settings.btcpay_host or not settings.btcpay_pem or not settings.btcpay_api_token:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="BTCPay settings are missing",
            )
        self._client = BTCPayClient(
            host=settings.btcpay_host.rstrip("/"),
            pem=settings.btcpay_pem,
            tokens={"merchant": settings.btcpay_api_token},
        )

    async def create_invoice(
        self,
        amount: Decimal,
        domme_wallet_id: str,
        sub_device_id: str,
    ) -> BTCPayInvoiceResult:
        payload = {
            "price": str(amount),
            "currency": "USD",
            "itemDesc": f"Obeisance invoice for device {sub_device_id}",
            "metadata": {
                "domme_wallet_id": domme_wallet_id,
                "sub_device_id": sub_device_id,
            },
        }
        invoice = await asyncio.to_thread(self._client.create_invoice, payload)
        invoice_id = str(invoice.get("id") or "")
        if not invoice_id:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="BTCPay invoice creation failed",
            )
        checkout_link = invoice.get("url") or invoice.get("checkoutLink")
        bitcoin_uri = invoice.get("bitcoinURI") or invoice.get("bitcoin_uri")
        return BTCPayInvoiceResult(
            invoice_id=invoice_id,
            checkout_link=checkout_link,
            bitcoin_uri=bitcoin_uri,
        )

