from __future__ import annotations

import logging
from uuid import UUID

from app.db.models import BillingCycle, User

logger = logging.getLogger(__name__)


async def notify_dom_billing_due(dom: User, cycle: BillingCycle) -> None:
    """Placeholder notifier for email/push billing reminders."""
    logger.info(
        "billing_due_notice dom_id=%s username=%s cycle_id=%s message=%s",
        dom.id,
        dom.username,
        cycle.id,
        "Your kennel infrastructure fee is due.",
    )


async def send_revoke_authority_command(device_id: UUID) -> None:
    """Placeholder FCM dispatch for authority revocation payload."""
    payload = {"command": "REVOKE_AUTHORITY", "fallback_state": "STAGING_MODE"}
    logger.warning("device_revoke_authority device_id=%s payload=%s", device_id, payload)


async def notify_dom_petition(
    *,
    dom_id: UUID,
    package_name: str,
    reason: str,
    petition_id: UUID,
) -> None:
    """Placeholder push dispatch for petition approval actions."""
    payload = {
        "type": "petition_request",
        "petition_id": str(petition_id),
        "package": package_name,
        "reason": reason,
        "actions": ["Approve 15m", "Deny"],
    }
    logger.info("dom_petition_push dom_id=%s payload=%s", dom_id, payload)
