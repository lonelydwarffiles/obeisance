"""API dependency definitions."""

from __future__ import annotations

import hashlib
from uuid import UUID

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import ApiKey, User, UserRole


def hash_api_key(raw_api_key: str) -> str:
	return hashlib.sha256(raw_api_key.encode("utf-8")).hexdigest()


async def get_current_user(
	db: AsyncSession = Depends(get_db),
	x_api_key: str | None = Header(default=None),
	x_mock_user_id: UUID | None = Header(default=None),
) -> User:
	if x_api_key:
		hashed = hash_api_key(x_api_key)
		api_key = (
			await db.execute(
				select(ApiKey).where(
					ApiKey.key_hash == hashed,
					ApiKey.is_active.is_(True),
				)
			)
		).scalar_one_or_none()
		if api_key is None:
			raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key")

		user = (await db.execute(select(User).where(User.id == api_key.domme_id))).scalar_one_or_none()
		if user is None or not user.is_active:
			raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User inactive or missing")
		return user

	if x_mock_user_id is not None:
		user = (await db.execute(select(User).where(User.id == x_mock_user_id))).scalar_one_or_none()
		if user is None:
			raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unknown mock user")
		return user

	raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required")


async def require_domme(current_user: User = Depends(get_current_user)) -> User:
	if current_user.role != UserRole.domme:
		raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Dom role required")
	return current_user


async def require_superadmin(current_user: User = Depends(get_current_user)) -> User:
	if current_user.role != UserRole.superadmin:
		raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Superadmin role required")
	return current_user
