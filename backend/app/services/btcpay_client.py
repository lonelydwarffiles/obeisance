from __future__ import annotations

import asyncio
from dataclasses import dataclass
from decimal import Decimal
import base64

import httpx

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


@dataclass(slots=True)
class LightningPayoutResult:
    payment_hash: str


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
        internal_invoice_id: str,
    ) -> BTCPayInvoiceResult:
        payload = {
            "price": str(amount),
            "currency": "USD",
            "itemDesc": f"Obeisance invoice for device {sub_device_id}",
            "metadata": {
                "internal_invoice_id": internal_invoice_id,
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

    async def resolve_lightning_address(self, destination: str, amount_sats: int) -> str:
        if "@" not in destination:
            return destination

        username, domain = destination.split("@", 1)
        lnurlp_url = f"https://{domain}/.well-known/lnurlp/{username}"
        async with httpx.AsyncClient(timeout=10) as client:
            lnurlp = (await client.get(lnurlp_url)).json()
            callback = lnurlp.get("callback")
            if not callback:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail="Invalid LNURL response for destination",
                )
            response = (
                await client.get(
                    callback,
                    params={"amount": amount_sats * 1000},
                )
            ).json()

        payment_request = response.get("pr")
        if not payment_request:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="LNURL callback did not return a payment request",
            )
        return str(payment_request)

    async def pay_lightning_invoice(self, payment_request: str) -> LightningPayoutResult:
        if not settings.lnd_rest_url or not settings.lnd_macaroon:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="LND payout settings are missing",
            )

        macaroon_hex = settings.lnd_macaroon
        cert = settings.lnd_cert_path or True
        payload = {
            "payment_request": payment_request,
            "fee_limit_sat": str(settings.lnd_fee_limit_sat),
        }

        async with httpx.AsyncClient(timeout=15, verify=cert) as client:
            response = await client.post(
                f"{settings.lnd_rest_url.rstrip('/')}/v1/channels/transactions",
                json=payload,
                headers={"Grpc-Metadata-macaroon": macaroon_hex},
            )

        if response.status_code >= 400:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"LND payout failed: {response.text}",
            )

        data = response.json()
        payment_hash = data.get("payment_hash")
        if not payment_hash and data.get("payment_hash") is None and data.get("payment_hash_str"):
            payment_hash = data.get("payment_hash_str")
        if isinstance(payment_hash, str):
            payment_hash_str = payment_hash
        elif isinstance(payment_hash, bytes):
            payment_hash_str = base64.b64encode(payment_hash).decode("ascii")
        else:
            payment_hash_str = str(payment_hash or "")

        if not payment_hash_str:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="LND payout did not return a payment hash",
            )

        return LightningPayoutResult(payment_hash=payment_hash_str)

    async def execute_lightning_payout(self, destination: str, amount_sats: int) -> LightningPayoutResult:
        if amount_sats <= 0:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Payout amount must be positive")

        payment_request = await self.resolve_lightning_address(destination, amount_sats)
        return await self.pay_lightning_invoice(payment_request)

