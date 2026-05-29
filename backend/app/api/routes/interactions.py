from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import and_, desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user, require_domme
from app.core.config import settings
from app.db.database import get_db
from app.db.models import (
    CommandStatus,
    InteractionReceipt,
    RelationshipCommand,
    RelationshipContract,
    RelationshipStatus,
    SafetyStopEvent,
    User,
)
from app.services.audit import record_audit_event

router = APIRouter(prefix="/interactions", tags=["interactions"])


DESTRUCTIVE_COMMANDS = {
    "lock_device",
    "restrict_packages",
    "revoke_authority",
    "wipe_data",
}


class RelationshipContractCreateRequest(BaseModel):
    sub_id: UUID
    device_id: UUID | None = None
    capabilities: list[str] = Field(default_factory=list)


class RelationshipContractStateRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=1000)


class RelationshipCapabilitiesRequest(BaseModel):
    capabilities: list[str] = Field(default_factory=list)


class RelationshipCommandRequest(BaseModel):
    command_type: str = Field(min_length=1, max_length=100)
    payload: dict = Field(default_factory=dict)
    requires_sub_ack: bool = False
    execute_after_seconds: int | None = Field(default=None, ge=0, le=3600)
    expires_after_seconds: int | None = Field(default=None, ge=60, le=86400)


class RelationshipCommandDecisionRequest(BaseModel):
    accepted: bool
    reason: str | None = Field(default=None, max_length=1000)


class SafetyStopRequest(BaseModel):
    reason: str = Field(min_length=1, max_length=1000)
    duration_minutes: int = Field(default=30, ge=5, le=240)


class RelationshipContractResponse(BaseModel):
    contract_id: UUID
    dom_id: UUID
    sub_id: UUID
    device_id: UUID | None
    status: str
    capabilities: list[str]
    consented_at: datetime | None
    paused_reason: str | None
    revoked_reason: str | None


class RelationshipCommandResponse(BaseModel):
    command_id: UUID
    contract_id: UUID
    command_type: str
    status: str
    requires_sub_ack: bool
    execute_after: datetime | None
    expires_at: datetime | None


class RelationshipCommandListResponse(BaseModel):
    commands: list[RelationshipCommandResponse]


class InteractionReceiptItem(BaseModel):
    receipt_id: UUID
    title: str
    detail: str
    created_at: datetime
    metadata: dict


class InteractionReceiptListResponse(BaseModel):
    receipts: list[InteractionReceiptItem]


class ActiveConstraintItem(BaseModel):
    key: str
    value: str
    reason: str | None = None
    expires_at: datetime | None = None


class ActiveConstraintResponse(BaseModel):
    contract_id: UUID
    constraints: list[ActiveConstraintItem]


def _contract_to_response(contract: RelationshipContract) -> RelationshipContractResponse:
    return RelationshipContractResponse(
        contract_id=contract.id,
        dom_id=contract.dom_id,
        sub_id=contract.sub_id,
        device_id=contract.device_id,
        status=contract.status.value,
        capabilities=contract.capabilities,
        consented_at=contract.consented_at,
        paused_reason=contract.paused_reason,
        revoked_reason=contract.revoked_reason,
    )


async def _get_contract_or_404(db: AsyncSession, contract_id: UUID) -> RelationshipContract:
    contract = (
        await db.execute(select(RelationshipContract).where(RelationshipContract.id == contract_id))
    ).scalar_one_or_none()
    if contract is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contract not found")
    return contract


@router.post("/contracts", response_model=RelationshipContractResponse, status_code=status.HTTP_201_CREATED)
async def create_relationship_contract(
    payload: RelationshipContractCreateRequest,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> RelationshipContractResponse:
    existing = (
        await db.execute(
            select(RelationshipContract).where(
                RelationshipContract.dom_id == dom_user.id,
                RelationshipContract.sub_id == payload.sub_id,
                RelationshipContract.device_id == payload.device_id,
                RelationshipContract.status != RelationshipStatus.archived,
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "message": "Contract already exists",
                "contract_id": str(existing.id),
            },
        )

    contract = RelationshipContract(
        dom_id=dom_user.id,
        sub_id=payload.sub_id,
        device_id=payload.device_id,
        status=RelationshipStatus.pending,
        capabilities=sorted(set(payload.capabilities)),
    )
    db.add(contract)
    await db.flush()

    db.add(
        InteractionReceipt(
            contract_id=contract.id,
            title="Relationship Contract Created",
            detail="A new contract is pending activation.",
            metadata_json={"status": contract.status.value},
            visible_to_sub=True,
        )
    )

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=payload.device_id,
        action="relationship_contract_created",
        target_type="relationship_contract",
        target_id=str(contract.id),
        metadata={"capabilities": contract.capabilities, "sub_id": str(payload.sub_id)},
    )
    await db.commit()
    return _contract_to_response(contract)


@router.get("/contracts/{contract_id}", response_model=RelationshipContractResponse)
async def get_relationship_contract(
    contract_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RelationshipContractResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if current_user.id not in {contract.dom_id, contract.sub_id}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")
    return _contract_to_response(contract)


@router.post("/contracts/{contract_id}/activate", response_model=RelationshipContractResponse)
async def activate_contract(
    contract_id: UUID,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> RelationshipContractResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if contract.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")

    contract.status = RelationshipStatus.active
    contract.consented_at = contract.consented_at or datetime.now(timezone.utc)
    contract.paused_reason = None
    contract.revoked_reason = None

    db.add(
        InteractionReceipt(
            contract_id=contract.id,
            title="Contract Activated",
            detail="Interaction controls are now active.",
            metadata_json={"status": contract.status.value},
            visible_to_sub=True,
        )
    )

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=contract.device_id,
        action="relationship_contract_activated",
        target_type="relationship_contract",
        target_id=str(contract.id),
        metadata={},
    )
    await db.commit()
    return _contract_to_response(contract)


@router.post("/contracts/{contract_id}/pause", response_model=RelationshipContractResponse)
async def pause_contract(
    contract_id: UUID,
    payload: RelationshipContractStateRequest,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> RelationshipContractResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if contract.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")

    contract.status = RelationshipStatus.paused
    contract.paused_reason = payload.reason

    db.add(
        InteractionReceipt(
            contract_id=contract.id,
            title="Contract Paused",
            detail="Interaction controls are paused.",
            metadata_json={"reason": payload.reason},
            visible_to_sub=True,
        )
    )

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=contract.device_id,
        action="relationship_contract_paused",
        target_type="relationship_contract",
        target_id=str(contract.id),
        metadata={"reason": payload.reason},
    )
    await db.commit()
    return _contract_to_response(contract)


@router.post("/contracts/{contract_id}/revoke", response_model=RelationshipContractResponse)
async def revoke_contract(
    contract_id: UUID,
    payload: RelationshipContractStateRequest,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> RelationshipContractResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if contract.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")

    contract.status = RelationshipStatus.revoked
    contract.revoked_reason = payload.reason

    db.add(
        InteractionReceipt(
            contract_id=contract.id,
            title="Contract Revoked",
            detail="Interaction controls were revoked.",
            metadata_json={"reason": payload.reason},
            visible_to_sub=True,
        )
    )

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=contract.device_id,
        action="relationship_contract_revoked",
        target_type="relationship_contract",
        target_id=str(contract.id),
        metadata={"reason": payload.reason},
    )
    await db.commit()
    return _contract_to_response(contract)


@router.post("/contracts/{contract_id}/archive", response_model=RelationshipContractResponse)
async def archive_contract(
    contract_id: UUID,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> RelationshipContractResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if contract.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")

    contract.status = RelationshipStatus.archived

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=contract.device_id,
        action="relationship_contract_archived",
        target_type="relationship_contract",
        target_id=str(contract.id),
        metadata={},
    )
    await db.commit()
    return _contract_to_response(contract)


@router.put("/contracts/{contract_id}/capabilities", response_model=RelationshipContractResponse)
async def update_contract_capabilities(
    contract_id: UUID,
    payload: RelationshipCapabilitiesRequest,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> RelationshipContractResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if contract.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")

    contract.capabilities = sorted(set(payload.capabilities))

    db.add(
        InteractionReceipt(
            contract_id=contract.id,
            title="Capabilities Updated",
            detail="Contract capability grants were changed.",
            metadata_json={"capabilities": contract.capabilities},
            visible_to_sub=True,
        )
    )

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=contract.device_id,
        action="relationship_capabilities_updated",
        target_type="relationship_contract",
        target_id=str(contract.id),
        metadata={"capabilities": contract.capabilities},
    )
    await db.commit()
    return _contract_to_response(contract)


@router.post("/contracts/{contract_id}/commands", response_model=RelationshipCommandResponse, status_code=status.HTTP_201_CREATED)
async def issue_dom_command(
    contract_id: UUID,
    payload: RelationshipCommandRequest,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> RelationshipCommandResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if contract.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")
    if contract.status != RelationshipStatus.active:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Contract is not active")
    if payload.command_type not in set(contract.capabilities):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Capability not granted")

    now = datetime.now(timezone.utc)
    rate_window = now - timedelta(seconds=settings.interaction_rate_window_seconds)
    issued_in_window = (
        await db.execute(
            select(func.count(RelationshipCommand.id)).where(
                RelationshipCommand.contract_id == contract.id,
                RelationshipCommand.created_at >= rate_window,
            )
        )
    ).scalar_one() or 0

    if issued_in_window >= settings.interaction_rate_limit_per_window:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Rate limit exceeded")

    cooldown_window = now - timedelta(seconds=settings.interaction_cooldown_seconds)
    duplicate_command = (
        await db.execute(
            select(RelationshipCommand)
            .where(
                RelationshipCommand.contract_id == contract.id,
                RelationshipCommand.command_type == payload.command_type,
                RelationshipCommand.created_at >= cooldown_window,
            )
            .order_by(desc(RelationshipCommand.created_at))
            .limit(1)
        )
    ).scalar_one_or_none()
    if duplicate_command is not None:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Command cooldown active")

    safe_mode = (
        await db.execute(
            select(SafetyStopEvent).where(
                SafetyStopEvent.contract_id == contract.id,
                SafetyStopEvent.active.is_(True),
                SafetyStopEvent.expires_at > now,
            )
        )
    ).scalar_one_or_none()
    if safe_mode is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Safe mode currently active")

    execute_after = now + timedelta(seconds=payload.execute_after_seconds or 0)
    expires_at = now + timedelta(seconds=payload.expires_after_seconds) if payload.expires_after_seconds else None
    requires_confirmation = payload.command_type in DESTRUCTIVE_COMMANDS

    command = RelationshipCommand(
        contract_id=contract.id,
        command_type=payload.command_type,
        payload_json=payload.payload,
        status=CommandStatus.pending_confirmation if requires_confirmation else CommandStatus.queued,
        requires_sub_ack=payload.requires_sub_ack,
        requested_by_dom_id=dom_user.id,
        execute_after=execute_after,
        expires_at=expires_at,
    )
    db.add(command)
    await db.flush()

    db.add(
        InteractionReceipt(
            contract_id=contract.id,
            command_id=command.id,
            title="Command Issued",
            detail=f"Command {payload.command_type} queued.",
            metadata_json={
                "command_type": payload.command_type,
                "status": command.status.value,
                "requires_confirmation": requires_confirmation,
            },
            visible_to_sub=True,
        )
    )

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=contract.device_id,
        action="relationship_command_issued",
        target_type="relationship_command",
        target_id=str(command.id),
        metadata={"command_type": payload.command_type, "status": command.status.value},
    )
    await db.commit()

    return RelationshipCommandResponse(
        command_id=command.id,
        contract_id=command.contract_id,
        command_type=command.command_type,
        status=command.status.value,
        requires_sub_ack=command.requires_sub_ack,
        execute_after=command.execute_after,
        expires_at=command.expires_at,
    )


@router.post("/commands/{command_id}/confirm", response_model=RelationshipCommandResponse)
async def confirm_destructive_command(
    command_id: UUID,
    db: AsyncSession = Depends(get_db),
    dom_user: User = Depends(require_domme),
) -> RelationshipCommandResponse:
    command = (
        await db.execute(select(RelationshipCommand).where(RelationshipCommand.id == command_id))
    ).scalar_one_or_none()
    if command is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Command not found")

    contract = await _get_contract_or_404(db, command.contract_id)
    if contract.dom_id != dom_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to command")

    if command.status != CommandStatus.pending_confirmation:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Command is not awaiting confirmation")

    command.status = CommandStatus.queued

    db.add(
        InteractionReceipt(
            contract_id=contract.id,
            command_id=command.id,
            title="Command Confirmed",
            detail=f"Command {command.command_type} confirmed for execution.",
            metadata_json={"status": command.status.value},
            visible_to_sub=True,
        )
    )

    await record_audit_event(
        db=db,
        actor_user_id=dom_user.id,
        device_id=contract.device_id,
        action="relationship_command_confirmed",
        target_type="relationship_command",
        target_id=str(command.id),
        metadata={"command_type": command.command_type},
    )
    await db.commit()

    return RelationshipCommandResponse(
        command_id=command.id,
        contract_id=command.contract_id,
        command_type=command.command_type,
        status=command.status.value,
        requires_sub_ack=command.requires_sub_ack,
        execute_after=command.execute_after,
        expires_at=command.expires_at,
    )


@router.post("/commands/{command_id}/ack", response_model=RelationshipCommandResponse)
async def acknowledge_or_reject_command(
    command_id: UUID,
    payload: RelationshipCommandDecisionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RelationshipCommandResponse:
    command = (
        await db.execute(select(RelationshipCommand).where(RelationshipCommand.id == command_id))
    ).scalar_one_or_none()
    if command is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Command not found")

    contract = await _get_contract_or_404(db, command.contract_id)
    if contract.sub_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only contract sub can respond")

    if command.status not in {CommandStatus.queued, CommandStatus.delivered}:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Command cannot be acknowledged")

    command.status = CommandStatus.acknowledged if payload.accepted else CommandStatus.rejected
    command.decided_at = datetime.now(timezone.utc)

    db.add(
        InteractionReceipt(
            contract_id=contract.id,
            command_id=command.id,
            title="Command Response",
            detail="Sub acknowledged command." if payload.accepted else "Sub rejected command.",
            metadata_json={"reason": payload.reason, "status": command.status.value},
            visible_to_sub=True,
        )
    )

    await record_audit_event(
        db=db,
        actor_user_id=current_user.id,
        device_id=contract.device_id,
        action="relationship_command_responded",
        target_type="relationship_command",
        target_id=str(command.id),
        metadata={"accepted": payload.accepted, "reason": payload.reason},
    )
    await db.commit()

    return RelationshipCommandResponse(
        command_id=command.id,
        contract_id=command.contract_id,
        command_type=command.command_type,
        status=command.status.value,
        requires_sub_ack=command.requires_sub_ack,
        execute_after=command.execute_after,
        expires_at=command.expires_at,
    )


@router.get("/contracts/{contract_id}/commands", response_model=RelationshipCommandListResponse)
async def list_contract_commands(
    contract_id: UUID,
    limit: int = Query(default=30, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RelationshipCommandListResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if current_user.id not in {contract.dom_id, contract.sub_id}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")

    commands = (
        await db.execute(
            select(RelationshipCommand)
            .where(RelationshipCommand.contract_id == contract.id)
            .order_by(desc(RelationshipCommand.created_at))
            .limit(limit)
        )
    ).scalars().all()

    return RelationshipCommandListResponse(
        commands=[
            RelationshipCommandResponse(
                command_id=item.id,
                contract_id=item.contract_id,
                command_type=item.command_type,
                status=item.status.value,
                requires_sub_ack=item.requires_sub_ack,
                execute_after=item.execute_after,
                expires_at=item.expires_at,
            )
            for item in commands
        ]
    )


@router.post("/contracts/{contract_id}/safe-mode", response_model=ActiveConstraintResponse)
async def trigger_safe_mode(
    contract_id: UUID,
    payload: SafetyStopRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ActiveConstraintResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if contract.sub_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only contract sub can trigger safe mode")

    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(minutes=payload.duration_minutes)

    active_safe_mode = (
        await db.execute(
            select(SafetyStopEvent).where(
                SafetyStopEvent.contract_id == contract.id,
                SafetyStopEvent.active.is_(True),
                SafetyStopEvent.expires_at > now,
            )
        )
    ).scalar_one_or_none()
    if active_safe_mode is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Safe mode already active")

    event = SafetyStopEvent(
        contract_id=contract.id,
        triggered_by_sub_id=current_user.id,
        reason=payload.reason,
        active=True,
        expires_at=expires_at,
    )
    db.add(event)

    db.add(
        InteractionReceipt(
            contract_id=contract.id,
            title="Emergency Safe Mode",
            detail="Temporary safe mode activated by sub.",
            metadata_json={"reason": payload.reason, "expires_at": expires_at.isoformat()},
            visible_to_sub=True,
        )
    )

    await record_audit_event(
        db=db,
        actor_user_id=current_user.id,
        device_id=contract.device_id,
        action="relationship_safe_mode_triggered",
        target_type="relationship_contract",
        target_id=str(contract.id),
        metadata={"reason": payload.reason, "expires_at": expires_at.isoformat()},
    )
    await db.commit()

    return ActiveConstraintResponse(
        contract_id=contract.id,
        constraints=[
            ActiveConstraintItem(
                key="safe_mode",
                value="active",
                reason=payload.reason,
                expires_at=expires_at,
            )
        ],
    )


@router.get("/contracts/{contract_id}/active-constraints", response_model=ActiveConstraintResponse)
async def list_active_constraints(
    contract_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ActiveConstraintResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if current_user.id not in {contract.dom_id, contract.sub_id}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")

    now = datetime.now(timezone.utc)

    active_safe_mode = (
        await db.execute(
            select(SafetyStopEvent).where(
                SafetyStopEvent.contract_id == contract.id,
                SafetyStopEvent.active.is_(True),
                SafetyStopEvent.expires_at > now,
            )
        )
    ).scalar_one_or_none()

    queued_commands = (
        await db.execute(
            select(RelationshipCommand)
            .where(
                RelationshipCommand.contract_id == contract.id,
                RelationshipCommand.status.in_([CommandStatus.queued, CommandStatus.delivered]),
                or_(
                    RelationshipCommand.expires_at.is_(None),
                    RelationshipCommand.expires_at > now,
                ),
            )
            .order_by(desc(RelationshipCommand.created_at))
            .limit(10)
        )
    ).scalars().all()

    constraints: list[ActiveConstraintItem] = []
    if contract.status == RelationshipStatus.paused:
        constraints.append(
            ActiveConstraintItem(key="contract_status", value="paused", reason=contract.paused_reason)
        )
    if contract.status == RelationshipStatus.revoked:
        constraints.append(
            ActiveConstraintItem(key="contract_status", value="revoked", reason=contract.revoked_reason)
        )
    if active_safe_mode is not None:
        constraints.append(
            ActiveConstraintItem(
                key="safe_mode",
                value="active",
                reason=active_safe_mode.reason,
                expires_at=active_safe_mode.expires_at,
            )
        )

    for command in queued_commands:
        constraints.append(
            ActiveConstraintItem(
                key="pending_command",
                value=command.command_type,
                reason=f"status={command.status.value}",
                expires_at=command.expires_at,
            )
        )

    return ActiveConstraintResponse(contract_id=contract.id, constraints=constraints)


@router.get("/contracts/{contract_id}/receipts", response_model=InteractionReceiptListResponse)
async def list_receipts(
    contract_id: UUID,
    include_hidden: bool = Query(default=False),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> InteractionReceiptListResponse:
    contract = await _get_contract_or_404(db, contract_id)
    if current_user.id not in {contract.dom_id, contract.sub_id}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No access to contract")

    visibility_filter = []
    if current_user.id == contract.sub_id:
        visibility_filter.append(InteractionReceipt.visible_to_sub.is_(True))
    elif not include_hidden:
        visibility_filter.append(InteractionReceipt.visible_to_sub.is_(True))

    query = select(InteractionReceipt).where(InteractionReceipt.contract_id == contract.id)
    if visibility_filter:
        query = query.where(and_(*visibility_filter))

    receipts = (
        await db.execute(
            query.order_by(desc(InteractionReceipt.created_at)).limit(100)
        )
    ).scalars().all()

    return InteractionReceiptListResponse(
        receipts=[
            InteractionReceiptItem(
                receipt_id=item.id,
                title=item.title,
                detail=item.detail,
                created_at=item.created_at,
                metadata=item.metadata_json,
            )
            for item in receipts
        ]
    )
