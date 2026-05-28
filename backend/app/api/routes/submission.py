from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import Device, DeviceStatus, SubmissionApplication, SubmissionStatus, User
from app.schemas.submission import SubmissionCreate, SubmissionResponse, SubmissionReview

router = APIRouter(tags=["submission"])


@router.post("/apply", response_model=SubmissionResponse, status_code=status.HTTP_201_CREATED)
async def apply_for_submission(
    payload: SubmissionCreate, db: AsyncSession = Depends(get_db)
) -> SubmissionResponse:
    result = await db.execute(select(User).where(User.static_link_id == payload.static_link_id))
    controller = result.scalar_one_or_none()
    if controller is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid static_link_id")

    application = SubmissionApplication(
        controller_id=controller.id,
        hardware_uuid=payload.hardware_uuid,
        device_model=payload.device_model,
        os_version=payload.os_version,
        battery_percentage=payload.battery_percentage,
        status=SubmissionStatus.pending,
    )
    db.add(application)

    device_result = await db.execute(select(Device).where(Device.hardware_uuid == payload.hardware_uuid))
    device = device_result.scalar_one_or_none()
    if device is None:
        device = Device(
            controller_id=controller.id,
            hardware_uuid=payload.hardware_uuid,
            status=DeviceStatus.pending,
        )
        db.add(device)
    else:
        device.controller_id = controller.id
        device.status = DeviceStatus.pending

    await db.commit()
    await db.refresh(application)

    return SubmissionResponse(id=application.id, status=application.status.value)


@router.get("/manage/applications", response_model=list[SubmissionResponse])
async def list_pending_applications(
    db: AsyncSession = Depends(get_db), x_mock_domme_user_id: UUID | None = Header(default=None)
) -> list[SubmissionResponse]:
    if x_mock_domme_user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing mock Domme user id")

    result = await db.execute(
        select(SubmissionApplication).where(
            SubmissionApplication.controller_id == x_mock_domme_user_id,
            SubmissionApplication.status == SubmissionStatus.pending,
        )
    )
    applications = result.scalars().all()
    return [SubmissionResponse(id=app.id, status=app.status.value) for app in applications]


@router.post("/manage/applications/{application_id}/review", response_model=SubmissionResponse)
async def review_submission_application(
    application_id: UUID,
    review: SubmissionReview,
    db: AsyncSession = Depends(get_db),
    x_mock_domme_user_id: UUID | None = Header(default=None),
) -> SubmissionResponse:
    if x_mock_domme_user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing mock Domme user id")

    result = await db.execute(
        select(SubmissionApplication).where(
            SubmissionApplication.id == application_id,
            SubmissionApplication.controller_id == x_mock_domme_user_id,
        )
    )
    application = result.scalar_one_or_none()
    if application is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Application not found")

    device_result = await db.execute(select(Device).where(Device.hardware_uuid == application.hardware_uuid))
    device = device_result.scalar_one_or_none()

    if review.action.value == "approve":
        application.status = SubmissionStatus.approved
        if device is not None:
            device.status = DeviceStatus.subservient
            device.controller_id = x_mock_domme_user_id
    else:
        application.status = SubmissionStatus.rejected
        if device is not None:
            device.status = DeviceStatus.dormant
            device.controller_id = x_mock_domme_user_id

    await db.commit()
    await db.refresh(application)

    return SubmissionResponse(id=application.id, status=application.status.value)
