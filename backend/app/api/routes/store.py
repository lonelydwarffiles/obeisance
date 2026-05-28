from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel
from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import Device, GraceLedger, StoreItem, StoreItemScope

router = APIRouter(tags=["store"])

CENTRAL_STORE_ITEMS: list[dict[str, str | int]] = [
    {
        "title": "Temporary 15-Minute App Unlock",
        "description": "Temporarily unlocks restricted apps for 15 minutes.",
        "cost": 100,
    },
    {
        "title": "Emergency 5-Minute Call Allowance",
        "description": "Allows urgent calls for a 5-minute emergency window.",
        "cost": 250,
    },
    {
        "title": "Request 24-Hour Task Extension",
        "description": "Submits a request to extend a task deadline by 24 hours.",
        "cost": 500,
    },
]

AUTOMATED_MDM_ITEM_ACTIONS: dict[str, str] = {
    "Temporary 15-Minute App Unlock": "temporary_unlock_15m",
    "Emergency 5-Minute Call Allowance": "emergency_call_allowance_5m",
    "Request 24-Hour Task Extension": "request_task_extension_24h",
}


class StoreItemResponse(BaseModel):
    id: UUID
    title: str
    description: str
    cost: int
    scope: str
    is_central: bool


class StorePurchaseRequest(BaseModel):
    device_id: UUID


class StorePurchaseResponse(BaseModel):
    purchase_logged: bool
    automated_action_triggered: bool
    remaining_balance: int
    ledger_entry_id: UUID


async def trigger_mdm_action(device_id: UUID, action: str) -> None:
    # TODO: publish MQTT command for device-specific automated store actions.
    _ = (device_id, action)


async def ensure_central_items_seeded(db: AsyncSession) -> None:
    seeded = False
    for item in CENTRAL_STORE_ITEMS:
        result = await db.execute(
            select(StoreItem).where(
                StoreItem.title == item["title"],
                StoreItem.scope == StoreItemScope.central_global,
            )
        )
        existing = result.scalar_one_or_none()
        if existing is not None:
            continue

        db.add(
            StoreItem(
                creator_id=None,
                title=str(item["title"]),
                description=str(item["description"]),
                cost=int(item["cost"]),
                scope=StoreItemScope.central_global,
                target_device_id=None,
                is_active=True,
            )
        )
        seeded = True

    if seeded:
        await db.commit()


async def get_visible_store_items(db: AsyncSession, device: Device) -> list[StoreItem]:
    result = await db.execute(
        select(StoreItem)
        .where(
            StoreItem.is_active.is_(True),
            or_(
                StoreItem.scope == StoreItemScope.central_global,
                and_(
                    StoreItem.scope == StoreItemScope.domme_global,
                    StoreItem.creator_id == device.leased_to_id,
                ),
                and_(
                    StoreItem.scope == StoreItemScope.sub_specific,
                    StoreItem.target_device_id == device.id,
                ),
            ),
        )
        .order_by(StoreItem.cost.asc(), StoreItem.title.asc())
    )
    return list(result.scalars().all())


@router.get("/store/{device_id}", response_model=list[StoreItemResponse], status_code=status.HTTP_200_OK)
async def list_store_items(
    device_id: UUID, response: Response, db: AsyncSession = Depends(get_db)
) -> list[StoreItemResponse]:
    await ensure_central_items_seeded(db)

    device_result = await db.execute(select(Device).where(Device.id == device_id))
    device = device_result.scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")

    balance_result = await db.execute(
        select(func.coalesce(func.sum(GraceLedger.amount), 0)).where(GraceLedger.device_id == device_id)
    )
    response.headers["X-Grace-Balance"] = str(int(balance_result.scalar_one()))

    items = await get_visible_store_items(db, device)
    return [
        StoreItemResponse(
            id=item.id,
            title=item.title,
            description=item.description,
            cost=item.cost,
            scope=item.scope.value,
            is_central=item.scope == StoreItemScope.central_global,
        )
        for item in items
    ]


@router.post("/store/purchase/{item_id}", response_model=StorePurchaseResponse, status_code=status.HTTP_201_CREATED)
async def purchase_store_item(
    item_id: UUID, payload: StorePurchaseRequest, db: AsyncSession = Depends(get_db)
) -> StorePurchaseResponse:
    await ensure_central_items_seeded(db)

    device_result = await db.execute(select(Device).where(Device.id == payload.device_id))
    device = device_result.scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")

    item_result = await db.execute(
        select(StoreItem).where(
            StoreItem.id == item_id,
            StoreItem.is_active.is_(True),
        )
    )
    item = item_result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Store item not found")

    visible_items = await get_visible_store_items(db, device)
    if all(entry.id != item.id for entry in visible_items):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Store item is not available for this device")

    balance_result = await db.execute(
        select(func.coalesce(func.sum(GraceLedger.amount), 0)).where(GraceLedger.device_id == payload.device_id)
    )
    balance = int(balance_result.scalar_one())
    if balance < item.cost:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Insufficient Grace balance")

    ledger_entry = GraceLedger(
        device_id=payload.device_id,
        amount=-item.cost,
        reason=f"Store purchase: {item.title}",
    )
    db.add(ledger_entry)

    automated_action_triggered = False
    automated_action = AUTOMATED_MDM_ITEM_ACTIONS.get(item.title)
    if automated_action is not None:
        await trigger_mdm_action(payload.device_id, automated_action)
        automated_action_triggered = True

    await db.commit()
    await db.refresh(ledger_entry)

    return StorePurchaseResponse(
        purchase_logged=True,
        automated_action_triggered=automated_action_triggered,
        remaining_balance=balance - item.cost,
        ledger_entry_id=ledger_entry.id,
    )
