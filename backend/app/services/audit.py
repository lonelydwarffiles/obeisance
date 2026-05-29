from __future__ import annotations

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AuditLog


async def record_audit_event(
    *,
    db: AsyncSession,
    action: str,
    target_type: str,
    target_id: str,
    actor_user_id: UUID | None = None,
    device_id: UUID | None = None,
    metadata: dict | None = None,
) -> AuditLog:
    event = AuditLog(
        actor_user_id=actor_user_id,
        device_id=device_id,
        action=action,
        target_type=target_type,
        target_id=target_id,
        metadata_json=metadata or {},
    )
    db.add(event)
    await db.flush()
    return event
