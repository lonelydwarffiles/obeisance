import enum
import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Integer, String, func
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

    central_owner: Mapped[User] = relationship(back_populates="centrally_owned_devices", foreign_keys=[central_owner_id])
    leased_to: Mapped[User | None] = relationship(back_populates="leased_devices", foreign_keys=[leased_to_id])


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
