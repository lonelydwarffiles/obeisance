from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import DailyPrepTask, Device
from app.services.staging import StagingService

router = APIRouter(tags=["staging"])


class PrepTaskResponse(BaseModel):
    id: UUID
    title: str
    description: str
    sort_order: int


class StagingDashboardResponse(BaseModel):
    mode: str
    branding_name: str
    tasks: list[PrepTaskResponse]


@router.get("/staging/{device_id}", response_model=StagingDashboardResponse)
async def get_staging_dashboard(device_id: UUID, db: AsyncSession = Depends(get_db)) -> StagingDashboardResponse:
    try:
        payload = await StagingService.get_dashboard_payload(device_id, db)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    return StagingDashboardResponse(
        mode=payload.mode,
        branding_name=payload.branding_name,
        tasks=[
            PrepTaskResponse(
                id=t.id,
                title=t.title,
                description=t.description,
                sort_order=t.sort_order,
            )
            for t in payload.tasks
        ],
    )
