from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import require_superadmin
from app.db.database import get_db
from app.db.models import AuditLog, BillingCycle, BillingCycleStatus, Device, DeviceStatus, Petition, PetitionStatus, User, UserRole

router = APIRouter(prefix="/central", tags=["central"])


class CentralRecentAuditEvent(BaseModel):
    action: str
    target_type: str
    created_at: datetime


class CentralDashboardSummaryResponse(BaseModel):
    total_devices: int
    leased_devices: int
    lease_pending_devices: int
    unclaimed_devices: int
    active_dommes: int
    inactive_dommes: int
    pending_billing_cycles: int
    overdue_billing_cycles: int
    open_petitions: int
    overdue_doms: list[str]
    recent_audit_events: list[CentralRecentAuditEvent]


class CentralTrendPoint(BaseModel):
    day: date
    overdue_billing_cycles: int
    open_petitions: int


class CentralTrendResponse(BaseModel):
    points: list[CentralTrendPoint]


class InactiveDomEntry(BaseModel):
    dom_id: str
    username: str
    billing_renewal_date: datetime


class InactiveDomListResponse(BaseModel):
    doms: list[InactiveDomEntry]


class OverdueDomEntry(BaseModel):
    dom_id: str
    username: str
    overdue_cycle_count: int
    latest_overdue_at: datetime


class OverdueDomListResponse(BaseModel):
    doms: list[OverdueDomEntry]


class OpenPetitionEntry(BaseModel):
    petition_id: str
    dom_id: str
    dom_username: str
    package_name: str
    reason: str
    created_at: datetime


class OpenPetitionListResponse(BaseModel):
    petitions: list[OpenPetitionEntry]


@router.get("/dashboard-summary", response_model=CentralDashboardSummaryResponse, status_code=status.HTTP_200_OK)
async def get_central_dashboard_summary(
    db: AsyncSession = Depends(get_db),
    _current_superadmin: User = Depends(require_superadmin),
) -> CentralDashboardSummaryResponse:
    total_devices = (await db.execute(select(func.count(Device.id)))).scalar_one() or 0
    leased_devices = (
        await db.execute(select(func.count(Device.id)).where(Device.status == DeviceStatus.leased))
    ).scalar_one() or 0
    lease_pending_devices = (
        await db.execute(select(func.count(Device.id)).where(Device.status == DeviceStatus.lease_pending))
    ).scalar_one() or 0
    unclaimed_devices = (
        await db.execute(select(func.count(Device.id)).where(Device.status == DeviceStatus.unclaimed_pool))
    ).scalar_one() or 0

    active_dommes = (
        await db.execute(
            select(func.count(User.id)).where(
                User.role == UserRole.domme,
                User.is_active.is_(True),
            )
        )
    ).scalar_one() or 0
    inactive_dommes = (
        await db.execute(
            select(func.count(User.id)).where(
                User.role == UserRole.domme,
                User.is_active.is_(False),
            )
        )
    ).scalar_one() or 0

    pending_billing_cycles = (
        await db.execute(
            select(func.count(BillingCycle.id)).where(BillingCycle.status == BillingCycleStatus.pending)
        )
    ).scalar_one() or 0
    overdue_billing_cycles = (
        await db.execute(
            select(func.count(BillingCycle.id)).where(BillingCycle.status == BillingCycleStatus.overdue)
        )
    ).scalar_one() or 0

    open_petitions = (
        await db.execute(select(func.count(Petition.id)).where(Petition.status == PetitionStatus.submitted))
    ).scalar_one() or 0

    overdue_doms = (
        await db.execute(
            select(User.username)
            .join(BillingCycle, BillingCycle.dom_id == User.id)
            .where(BillingCycle.status == BillingCycleStatus.overdue)
            .order_by(desc(BillingCycle.created_at))
            .limit(8)
        )
    ).scalars().all()

    recent_audit_entries = (
        await db.execute(
            select(AuditLog)
            .order_by(desc(AuditLog.created_at))
            .limit(12)
        )
    ).scalars().all()

    return CentralDashboardSummaryResponse(
        total_devices=total_devices,
        leased_devices=leased_devices,
        lease_pending_devices=lease_pending_devices,
        unclaimed_devices=unclaimed_devices,
        active_dommes=active_dommes,
        inactive_dommes=inactive_dommes,
        pending_billing_cycles=pending_billing_cycles,
        overdue_billing_cycles=overdue_billing_cycles,
        open_petitions=open_petitions,
        overdue_doms=overdue_doms,
        recent_audit_events=[
            CentralRecentAuditEvent(
                action=entry.action,
                target_type=entry.target_type,
                created_at=entry.created_at,
            )
            for entry in recent_audit_entries
        ],
    )


@router.get("/trends", response_model=CentralTrendResponse, status_code=status.HTTP_200_OK)
async def get_central_trends(
    days: int = 7,
    db: AsyncSession = Depends(get_db),
    _current_superadmin: User = Depends(require_superadmin),
) -> CentralTrendResponse:
    days = max(1, min(days, 31))
    today = datetime.now(timezone.utc).date()
    start_day = today - timedelta(days=days - 1)

    overdue_rows = (
        await db.execute(
            select(
                func.date(BillingCycle.created_at),
                func.count(BillingCycle.id),
            )
            .where(
                BillingCycle.status == BillingCycleStatus.overdue,
                BillingCycle.created_at >= datetime.combine(start_day, datetime.min.time(), tzinfo=timezone.utc),
            )
            .group_by(func.date(BillingCycle.created_at))
        )
    ).all()

    petition_rows = (
        await db.execute(
            select(
                func.date(Petition.created_at),
                func.count(Petition.id),
            )
            .where(
                Petition.status == PetitionStatus.submitted,
                Petition.created_at >= datetime.combine(start_day, datetime.min.time(), tzinfo=timezone.utc),
            )
            .group_by(func.date(Petition.created_at))
        )
    ).all()

    overdue_by_day: dict[date, int] = defaultdict(int)
    for row_day, count in overdue_rows:
        if isinstance(row_day, date):
            overdue_by_day[row_day] = int(count or 0)

    petitions_by_day: dict[date, int] = defaultdict(int)
    for row_day, count in petition_rows:
        if isinstance(row_day, date):
            petitions_by_day[row_day] = int(count or 0)

    points = []
    for offset in range(days):
        day = start_day + timedelta(days=offset)
        points.append(
            CentralTrendPoint(
                day=day,
                overdue_billing_cycles=overdue_by_day.get(day, 0),
                open_petitions=petitions_by_day.get(day, 0),
            )
        )

    return CentralTrendResponse(points=points)


@router.get("/drilldown/inactive-doms", response_model=InactiveDomListResponse, status_code=status.HTTP_200_OK)
async def get_inactive_doms(
    db: AsyncSession = Depends(get_db),
    _current_superadmin: User = Depends(require_superadmin),
) -> InactiveDomListResponse:
    rows = (
        await db.execute(
            select(User)
            .where(
                User.role == UserRole.domme,
                User.is_active.is_(False),
            )
            .order_by(User.billing_renewal_date.asc())
            .limit(100)
        )
    ).scalars().all()

    return InactiveDomListResponse(
        doms=[
            InactiveDomEntry(
                dom_id=str(row.id),
                username=row.username,
                billing_renewal_date=row.billing_renewal_date,
            )
            for row in rows
        ]
    )


@router.get("/drilldown/overdue-doms", response_model=OverdueDomListResponse, status_code=status.HTTP_200_OK)
async def get_overdue_doms(
    db: AsyncSession = Depends(get_db),
    _current_superadmin: User = Depends(require_superadmin),
) -> OverdueDomListResponse:
    rows = (
        await db.execute(
            select(
                User.id,
                User.username,
                func.count(BillingCycle.id).label("overdue_count"),
                func.max(BillingCycle.created_at).label("latest_overdue_at"),
            )
            .join(BillingCycle, BillingCycle.dom_id == User.id)
            .where(BillingCycle.status == BillingCycleStatus.overdue)
            .group_by(User.id, User.username)
            .order_by(desc(func.max(BillingCycle.created_at)))
            .limit(100)
        )
    ).all()

    return OverdueDomListResponse(
        doms=[
            OverdueDomEntry(
                dom_id=str(dom_id),
                username=username,
                overdue_cycle_count=int(overdue_count or 0),
                latest_overdue_at=latest_overdue_at,
            )
            for dom_id, username, overdue_count, latest_overdue_at in rows
            if latest_overdue_at is not None
        ]
    )


@router.get("/drilldown/open-petitions", response_model=OpenPetitionListResponse, status_code=status.HTTP_200_OK)
async def get_open_petitions(
    db: AsyncSession = Depends(get_db),
    _current_superadmin: User = Depends(require_superadmin),
) -> OpenPetitionListResponse:
    rows = (
        await db.execute(
            select(Petition, User.username)
            .join(User, User.id == Petition.dom_id)
            .where(Petition.status == PetitionStatus.submitted)
            .order_by(desc(Petition.created_at))
            .limit(100)
        )
    ).all()

    return OpenPetitionListResponse(
        petitions=[
            OpenPetitionEntry(
                petition_id=str(petition.id),
                dom_id=str(petition.dom_id),
                dom_username=dom_username,
                package_name=petition.package_name,
                reason=petition.reason,
                created_at=petition.created_at,
            )
            for petition, dom_username in rows
        ]
    )
