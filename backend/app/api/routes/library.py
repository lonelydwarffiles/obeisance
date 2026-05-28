from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import TerminologyLibrary, TerminologyStatus
from app.schemas.library import TermResponse, TermSuggestRequest

router = APIRouter(tags=["library"])


@router.get("/library", response_model=list[TermResponse])
async def list_approved_terms(db: AsyncSession = Depends(get_db)) -> list[TermResponse]:
    result = await db.execute(
        select(TerminologyLibrary).where(TerminologyLibrary.status == TerminologyStatus.approved)
    )
    terms = result.scalars().all()
    return [
        TermResponse(id=t.id, category=t.category, term=t.term, status=t.status.value)
        for t in terms
    ]


@router.post("/library/suggest", response_model=TermResponse, status_code=status.HTTP_201_CREATED)
async def suggest_term(
    payload: TermSuggestRequest,
    db: AsyncSession = Depends(get_db),
    x_mock_domme_user_id: UUID | None = Header(default=None),
) -> TermResponse:
    if x_mock_domme_user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing Domme user id")
    term = TerminologyLibrary(
        category=payload.category,
        term=payload.term,
        status=TerminologyStatus.pending,
        creator_id=x_mock_domme_user_id,
    )
    db.add(term)
    await db.commit()
    await db.refresh(term)
    return TermResponse(id=term.id, category=term.category, term=term.term, status=term.status.value)


@router.get("/admin/pending-terms", response_model=list[TermResponse])
async def list_pending_terms(db: AsyncSession = Depends(get_db)) -> list[TermResponse]:
    result = await db.execute(
        select(TerminologyLibrary).where(TerminologyLibrary.status == TerminologyStatus.pending)
    )
    terms = result.scalars().all()
    return [
        TermResponse(id=t.id, category=t.category, term=t.term, status=t.status.value)
        for t in terms
    ]


@router.put("/admin/approve-term/{term_id}", response_model=TermResponse)
async def approve_term(term_id: UUID, db: AsyncSession = Depends(get_db)) -> TermResponse:
    result = await db.execute(select(TerminologyLibrary).where(TerminologyLibrary.id == term_id))
    term = result.scalar_one_or_none()
    if term is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Term not found")
    term.status = TerminologyStatus.approved
    await db.commit()
    await db.refresh(term)
    return TermResponse(id=term.id, category=term.category, term=term.term, status=term.status.value)
