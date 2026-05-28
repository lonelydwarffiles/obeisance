import enum
import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Integer, Numeric, String, func
from sqlalchemy.dialects.postgresql import UUID
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
