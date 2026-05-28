import secrets
from dataclasses import dataclass
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Device, InviteLink, Tenant


@dataclass(slots=True)
class GrowthStats:
    active_subs: int
    total_slots: int


def _generate_slug(length: int = 10) -> str:
    return secrets.token_urlsafe(length)[:length].lower()


async def create_invite_link(creator_id: UUID, db: AsyncSession) -> InviteLink:
    slug = _generate_slug()
    while (await db.execute(select(InviteLink).where(InviteLink.slug == slug))).scalar_one_or_none() is not None:
        slug = _generate_slug()

    invite = InviteLink(creator_id=creator_id, slug=slug, is_active=True)
    db.add(invite)
    await db.commit()
    await db.refresh(invite)
    return invite


async def process_signup(invite_slug: str, db: AsyncSession) -> InviteLink:
    invite_result = await db.execute(
        select(InviteLink).where(
            InviteLink.slug == invite_slug,
            InviteLink.is_active.is_(True),
        )
    )
    invite = invite_result.scalar_one_or_none()
    if invite is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or inactive invite link")

    if invite.current_uses >= invite.max_uses:
        invite.is_active = False
        await db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invite link is exhausted")

    invite.current_uses += 1
    if invite.current_uses >= invite.max_uses:
        invite.is_active = False

    tenant_result = await db.execute(select(Tenant).where(Tenant.owner_id == invite.creator_id))
    tenant = tenant_result.scalar_one_or_none()
    if tenant is None:
        tenant = Tenant(owner_id=invite.creator_id, base_slots=0)
        db.add(tenant)

    tenant.base_slots += 1
    await db.commit()
    await db.refresh(invite)
    return invite


async def get_growth_stats(owner_id: UUID, db: AsyncSession) -> GrowthStats:
    tenant_result = await db.execute(select(Tenant).where(Tenant.owner_id == owner_id))
    tenant = tenant_result.scalar_one_or_none()
    total_slots = tenant.base_slots if tenant is not None else 0

    active_subs_result = await db.execute(
        select(func.count(Device.id)).where(Device.leased_to_id == owner_id)
    )
    active_subs = int(active_subs_result.scalar_one() or 0)

    return GrowthStats(active_subs=active_subs, total_slots=total_slots)
