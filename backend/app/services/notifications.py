from __future__ import annotations

import logging
from uuid import UUID

import httpx

from app.core.config import settings
from app.db.models import BillingCycle, User

logger = logging.getLogger(__name__)


async def _send_push_event(event_type: str, payload: dict) -> None:
    if not settings.push_gateway_url:
        logger.info("push_gateway_disabled event_type=%s payload=%s", event_type, payload)
        return

    headers = {"Content-Type": "application/json", "X-Event-Type": event_type}
    if settings.push_gateway_token:
        headers["Authorization"] = f"Bearer {settings.push_gateway_token}"

    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(settings.push_gateway_url, json=payload, headers=headers)
    if response.status_code >= 400:
        logger.warning(
            "push_gateway_failed status=%s body=%s event_type=%s",
            response.status_code,
            response.text,
            event_type,
        )


async def notify_dom_billing_due(dom: User, cycle: BillingCycle) -> None:
    payload = {
        "dom_id": str(dom.id),
        "username": dom.username,
        "cycle_id": str(cycle.id),
        "message": "Your kennel infrastructure fee is due.",
    }
    await _send_push_event("billing_due_notice", payload)


async def send_revoke_authority_command(device_id: UUID) -> None:
    payload = {"command": "REVOKE_AUTHORITY", "fallback_state": "STAGING_MODE"}
    await _send_push_event("device_revoke_authority", {"device_id": str(device_id), **payload})


async def notify_dom_petition(
    *,
    dom_id: UUID,
    package_name: str,
    reason: str,
    petition_id: UUID,
) -> None:
    payload = {
        "type": "petition_request",
        "petition_id": str(petition_id),
        "dom_id": str(dom_id),
        "package": package_name,
        "reason": reason,
        "actions": ["Approve 15m", "Deny"],
    }
    await _send_push_event("dom_petition_push", payload)
