import enum
import uuid
from datetime import datetime, time

from sqlalchemy import Boolean, DateTime, Enum, Float, ForeignKey, Integer, Numeric, String, Text, Time, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import ARRAY, JSON, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class DeviceStatus(str, enum.Enum):
    unclaimed_pool = "unclaimed_pool"
    lease_pending = "lease_pending"
    leased = "leased"


class UserRole(str, enum.Enum):
    superadmin = "superadmin"
    domme = "domme"


class SubmissionStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"


class TransactionStatus(str, enum.Enum):
    pending = "pending"
    completed = "completed"
    failed = "failed"


class StoreItemScope(str, enum.Enum):
    central_global = "central_global"
    domme_global = "domme_global"
    sub_specific = "sub_specific"


class TerminologyStatus(str, enum.Enum):
    approved = "approved"
    pending = "pending"


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    static_link_id: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    role: Mapped[UserRole] = mapped_column(Enum(UserRole, name="user_role"), nullable=False, default=UserRole.domme)

    centrally_owned_devices: Mapped[list["Device"]] = relationship(
        back_populates="central_owner",
        foreign_keys="Device.central_owner_id",
    )
    leased_devices: Mapped[list["Device"]] = relationship(
        back_populates="leased_to",
        foreign_keys="Device.leased_to_id",
    )
    wallet: Mapped["Wallet | None"] = relationship(back_populates="user", uselist=False, cascade="all, delete-orphan")
    lease_tiers: Mapped[list["LeaseTier"]] = relationship(back_populates="domme", cascade="all, delete-orphan")
    payments_made: Mapped[list["Transaction"]] = relationship(
        back_populates="paid_by",
        foreign_keys="Transaction.paid_by_id",
    )
    submission_applications: Mapped[list["SubmissionApplication"]] = relationship(
        back_populates="controller", cascade="all, delete-orphan"
    )
    api_keys: Mapped[list["ApiKey"]] = relationship(back_populates="domme", cascade="all, delete-orphan")
    webhook_endpoints: Mapped[list["WebhookEndpoint"]] = relationship(
        back_populates="domme", cascade="all, delete-orphan"
    )
    created_store_items: Mapped[list["StoreItem"]] = relationship(
        back_populates="creator",
        foreign_keys="StoreItem.creator_id",
    )


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    central_owner_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    leased_to_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    hardware_uuid: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    status: Mapped[DeviceStatus] = mapped_column(
        Enum(DeviceStatus, name="device_status"), default=DeviceStatus.unclaimed_pool, nullable=False
    )
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), server_default=func.now())
    lease_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    central_owner: Mapped[User] = relationship(back_populates="centrally_owned_devices", foreign_keys=[central_owner_id])
    leased_to: Mapped[User | None] = relationship(back_populates="leased_devices", foreign_keys=[leased_to_id])
    transactions: Mapped[list["Transaction"]] = relationship(back_populates="device", cascade="all, delete-orphan")
    grace_ledger_entries: Mapped[list["GraceLedger"]] = relationship(
        back_populates="device", cascade="all, delete-orphan"
    )
    rule_contracts: Mapped[list["RuleContract"]] = relationship(back_populates="device", cascade="all, delete-orphan")
    targeted_store_items: Mapped[list["StoreItem"]] = relationship(
        back_populates="target_device",
        foreign_keys="StoreItem.target_device_id",
    )


class ApiKey(Base):
    __tablename__ = "api_keys"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    domme_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    key_hash: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    label: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    domme: Mapped[User] = relationship(back_populates="api_keys")


class WebhookEndpoint(Base):
    __tablename__ = "webhook_endpoints"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    domme_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    target_url: Mapped[str] = mapped_column(String(1024), nullable=False)
    secret_token: Mapped[str] = mapped_column(String(255), nullable=False)
    event_types: Mapped[list[str]] = mapped_column(ARRAY(String), nullable=False, default=list)

    domme: Mapped[User] = relationship(back_populates="webhook_endpoints")


class GraceLedger(Base):
    __tablename__ = "grace_ledger"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    device: Mapped[Device] = relationship(back_populates="grace_ledger_entries")


class RuleContract(Base):
    __tablename__ = "rule_contracts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    require_photo_proof: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deadline_time: Mapped[time] = mapped_column(Time(timezone=False), nullable=False)
    days_of_week: Mapped[list[int]] = mapped_column(ARRAY(Integer), nullable=False, default=list)
    reward_grace: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    punishment_grace: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    auto_lock_on_fail: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    device: Mapped[Device] = relationship(back_populates="rule_contracts")


class StoreItem(Base):
    __tablename__ = "store_items"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    creator_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(String(1024), nullable=False)
    cost: Mapped[int] = mapped_column(Integer, nullable=False)
    scope: Mapped[StoreItemScope] = mapped_column(
        Enum(StoreItemScope, name="store_item_scope"), nullable=False, default=StoreItemScope.central_global
    )
    target_device_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id"), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    creator: Mapped[User | None] = relationship(back_populates="created_store_items", foreign_keys=[creator_id])
    target_device: Mapped[Device | None] = relationship(back_populates="targeted_store_items", foreign_keys=[target_device_id])


class SubmissionApplication(Base):
    __tablename__ = "submission_applications"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    controller_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    hardware_uuid: Mapped[str] = mapped_column(String(255), nullable=False)
    device_model: Mapped[str] = mapped_column(String(255), nullable=False)
    os_version: Mapped[str] = mapped_column(String(255), nullable=False)
    battery_percentage: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[SubmissionStatus] = mapped_column(
        Enum(SubmissionStatus, name="submission_status"), default=SubmissionStatus.pending, nullable=False
    )

    controller: Mapped[User] = relationship(back_populates="submission_applications")


class Wallet(Base):
    __tablename__ = "wallets"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), unique=True, nullable=False)
    balance_usdc: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0.0)
    withdrawal_address: Mapped[str | None] = mapped_column(String(255), nullable=True)

    user: Mapped[User] = relationship(back_populates="wallet")


class LeaseTier(Base):
    __tablename__ = "lease_tiers"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    domme_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    base_central_fee: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    domme_markup: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    domme: Mapped[User] = relationship(back_populates="lease_tiers")


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    paid_by_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    amount_total: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    central_cut: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    domme_cut: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    status: Mapped[TransactionStatus] = mapped_column(
        Enum(TransactionStatus, name="transaction_status"),
        default=TransactionStatus.pending,
        nullable=False,
    )
    external_tx_hash: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)

    device: Mapped[Device] = relationship(back_populates="transactions")
    paid_by: Mapped[User | None] = relationship(back_populates="payments_made", foreign_keys=[paid_by_id])


class SharedNote(Base):
    __tablename__ = "shared_notes"
    __table_args__ = (UniqueConstraint("device_id", name="uq_shared_notes_device"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False, default="")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    device: Mapped[Device] = relationship()


class DommeDossier(Base):
    __tablename__ = "domme_dossiers"
    __table_args__ = (UniqueConstraint("domme_id", "device_id", name="uq_domme_dossier_pair"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    domme_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    private_notes: Mapped[str] = mapped_column(Text, nullable=False, default="")  # encrypted at rest in service layer
    last_updated: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    domme: Mapped[User] = relationship(foreign_keys=[domme_id])
    device: Mapped[Device] = relationship(foreign_keys=[device_id])


class PersonaProfile(Base):
    __tablename__ = "persona_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    domme_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, unique=True
    )
    terminology_map: Mapped[dict] = mapped_column(
        JSON,
        nullable=False,
        default=lambda: {
            "sub_label": "Pet",
            "domme_label": "Mistress",
            "task_label": "Chore",
            "currency_label": "Credits",
        },
    )
    enabled_modules: Mapped[list[str]] = mapped_column(
        ARRAY(String),
        nullable=False,
        default=lambda: ["ledger", "knot", "proof_upload", "sensory"],
    )

    domme: Mapped[User] = relationship(foreign_keys=[domme_id])


class TerminologyLibrary(Base):
    __tablename__ = "terminology_library"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    category: Mapped[str] = mapped_column(String(100), nullable=False)  # e.g. "sub_label"
    term: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[TerminologyStatus] = mapped_column(
        Enum(TerminologyStatus, name="terminology_status"),
        nullable=False,
        default=TerminologyStatus.pending,
    )
    creator_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True  # null => created by Central
    )

    creator: Mapped[User | None] = relationship(foreign_keys=[creator_id])


class CandidateProfile(Base):
    __tablename__ = "candidate_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id"), unique=True, nullable=False
    )
    anonymized_interests: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    readiness_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    is_published: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    device: Mapped[Device] = relationship(foreign_keys=[device_id])


class DailyPrepTask(Base):
    __tablename__ = "daily_prep_tasks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
