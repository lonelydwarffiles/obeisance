from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import DommeDossier, SharedNote
from app.schemas.notes import DossierResponse, DossierUpdate, SharedNoteResponse, SharedNoteUpdate

router = APIRouter(tags=["notes"])


@router.get("/notes/shared/{device_id}", response_model=SharedNoteResponse)
async def get_shared_note(device_id: UUID, db: AsyncSession = Depends(get_db)) -> SharedNoteResponse:
    result = await db.execute(select(SharedNote).where(SharedNote.device_id == device_id))
    note = result.scalar_one_or_none()
    if note is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shared note not found")
    return SharedNoteResponse(
        id=note.id,
        device_id=note.device_id,
        content=note.content,
        updated_at=note.updated_at,
    )


@router.put("/notes/shared/{device_id}", response_model=SharedNoteResponse)
async def upsert_shared_note(
    device_id: UUID, payload: SharedNoteUpdate, db: AsyncSession = Depends(get_db)
) -> SharedNoteResponse:
    result = await db.execute(select(SharedNote).where(SharedNote.device_id == device_id))
    note = result.scalar_one_or_none()
    if note is None:
        note = SharedNote(device_id=device_id, content=payload.content)
        db.add(note)
    else:
        note.content = payload.content
        note.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(note)
    return SharedNoteResponse(
        id=note.id,
        device_id=note.device_id,
        content=note.content,
        updated_at=note.updated_at,
    )


@router.get("/notes/dossier/{device_id}", response_model=DossierResponse)
async def get_dossier(
    device_id: UUID,
    db: AsyncSession = Depends(get_db),
    x_mock_domme_user_id: UUID | None = Header(default=None),
) -> DossierResponse:
    if x_mock_domme_user_id is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Domme access required")
    result = await db.execute(
        select(DommeDossier).where(
            DommeDossier.device_id == device_id,
            DommeDossier.domme_id == x_mock_domme_user_id,
        )
    )
    dossier = result.scalar_one_or_none()
    if dossier is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dossier not found")
    return DossierResponse(
        id=dossier.id,
        domme_id=dossier.domme_id,
        device_id=dossier.device_id,
        private_notes=dossier.private_notes,
        last_updated=dossier.last_updated,
    )


@router.put("/notes/dossier/{device_id}", response_model=DossierResponse)
async def upsert_dossier(
    device_id: UUID,
    payload: DossierUpdate,
    db: AsyncSession = Depends(get_db),
    x_mock_domme_user_id: UUID | None = Header(default=None),
) -> DossierResponse:
    if x_mock_domme_user_id is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Domme access required")
    result = await db.execute(
        select(DommeDossier).where(
            DommeDossier.device_id == device_id,
            DommeDossier.domme_id == x_mock_domme_user_id,
        )
    )
    dossier = result.scalar_one_or_none()
    if dossier is None:
        dossier = DommeDossier(
            domme_id=x_mock_domme_user_id,
            device_id=device_id,
            private_notes=payload.private_notes,
        )
        db.add(dossier)
    else:
        dossier.private_notes = payload.private_notes
        dossier.last_updated = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(dossier)
    return DossierResponse(
        id=dossier.id,
        domme_id=dossier.domme_id,
        device_id=dossier.device_id,
        private_notes=dossier.private_notes,
        last_updated=dossier.last_updated,
    )
