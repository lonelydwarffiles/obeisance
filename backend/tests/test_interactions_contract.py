from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.api.dependencies import get_current_user, require_domme
from app.db.database import get_db
from app.main import app


class _ScalarProxy:
    def __init__(self, values):
        self._values = values

    def all(self):
        return self._values


class _ExecuteResult:
    def __init__(self, *, scalar_value=None, scalar_values=None):
        self._scalar_value = scalar_value
        self._scalar_values = scalar_values or []

    def scalar_one(self):
        return self._scalar_value

    def scalar_one_or_none(self):
        return self._scalar_value

    def scalars(self):
        return _ScalarProxy(self._scalar_values)


class _FakeSession:
    def __init__(self):
        self.storage: dict[str, object] = {}

    async def execute(self, statement):
        sql_text = str(statement)

        if "FROM relationship_contracts" in sql_text and "WHERE relationship_contracts.id" in sql_text:
            return _ExecuteResult(scalar_value=self.storage.get("contract"))

        if "count(relationship_commands.id)" in sql_text:
            return _ExecuteResult(scalar_value=0)

        if "FROM relationship_commands" in sql_text and "created_at >=" in sql_text:
            return _ExecuteResult(scalar_value=None)

        if "FROM safety_stop_events" in sql_text:
            return _ExecuteResult(scalar_value=None)

        if "FROM interaction_receipts" in sql_text:
            receipts = self.storage.get("receipts") or []
            return _ExecuteResult(scalar_values=receipts)

        if "FROM relationship_commands" in sql_text and "WHERE relationship_commands.id" in sql_text:
            return _ExecuteResult(scalar_value=self.storage.get("command"))

        return _ExecuteResult(scalar_value=None)

    def add(self, item):
        if hasattr(item, "dom_id") and hasattr(item, "sub_id"):
            if getattr(item, "id", None) is None:
                item.id = uuid4()
            self.storage["contract"] = item
        if hasattr(item, "command_type") and hasattr(item, "contract_id"):
            if getattr(item, "id", None) is None:
                item.id = uuid4()
            self.storage["command"] = item

        if hasattr(item, "title") and hasattr(item, "detail"):
            receipts = self.storage.get("receipts")
            if receipts is None:
                receipts = []
                self.storage["receipts"] = receipts
            if getattr(item, "id", None) is None:
                item.id = uuid4()
            if getattr(item, "created_at", None) is None:
                item.created_at = datetime.now(timezone.utc)
            receipts.append(item)

    async def flush(self):
        return None

    async def commit(self):
        return None


@pytest.mark.asyncio
async def test_create_activate_and_receipts_flow() -> None:
    fake_db = _FakeSession()
    dom_id = uuid4()
    sub_id = uuid4()

    async def _override_db():
        yield fake_db

    async def _override_domme_user():
        return SimpleNamespace(id=dom_id)

    async def _override_current_user():
        return SimpleNamespace(id=sub_id)

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[require_domme] = _override_domme_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        create_resp = await client.post(
            "/api/interactions/contracts",
            json={"sub_id": str(sub_id), "capabilities": ["lock_device", "message_sub"]},
        )
        assert create_resp.status_code == 201
        contract_id = create_resp.json()["contract_id"]

        activate_resp = await client.post(f"/api/interactions/contracts/{contract_id}/activate")
        assert activate_resp.status_code == 200
        assert activate_resp.json()["status"] == "active"

        app.dependency_overrides[get_current_user] = _override_current_user
        receipts_resp = await client.get(f"/api/interactions/contracts/{contract_id}/receipts")
        assert receipts_resp.status_code == 200
        payload = receipts_resp.json()
        assert len(payload["receipts"]) >= 2

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_command_requires_confirmation_for_destructive_types() -> None:
    fake_db = _FakeSession()
    dom_id = uuid4()
    sub_id = uuid4()

    contract = SimpleNamespace(
        id=uuid4(),
        dom_id=dom_id,
        sub_id=sub_id,
        device_id=None,
        status=SimpleNamespace(value="active") if False else None,
        capabilities=["lock_device", "message_sub"],
    )
    # Use real enum value strings through interface constraints.
    contract.status = SimpleNamespace(value="active")

    # route code compares direct enum; emulate by matching expected attr via monkey object
    class _Status:
        value = "active"

        def __eq__(self, other):
            return getattr(other, "value", other) == "active"

    contract.status = _Status()
    fake_db.storage["contract"] = contract

    async def _override_db():
        yield fake_db

    async def _override_domme_user():
        return SimpleNamespace(id=dom_id)

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[require_domme] = _override_domme_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.post(
            f"/api/interactions/contracts/{contract.id}/commands",
            json={
                "command_type": "lock_device",
                "payload": {"source": "test"},
                "requires_sub_ack": True,
                "expires_after_seconds": 300,
            },
        )

    assert response.status_code == 201
    assert response.json()["status"] == "pending_confirmation"

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_safe_mode_constraint_visibility() -> None:
    fake_db = _FakeSession()
    dom_id = uuid4()
    sub_id = uuid4()

    class _Status:
        value = "active"

        def __eq__(self, other):
            return getattr(other, "value", other) == "active"

    fake_db.storage["contract"] = SimpleNamespace(
        id=uuid4(),
        dom_id=dom_id,
        sub_id=sub_id,
        device_id=None,
        status=_Status(),
        capabilities=["lock_device"],
        paused_reason=None,
        revoked_reason=None,
    )

    fake_db.storage["safe_mode"] = SimpleNamespace(
        contract_id=fake_db.storage["contract"].id,
        active=True,
        reason="panic",
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
    )

    async def _override_db():
        yield fake_db

    async def _override_current_user():
        return SimpleNamespace(id=sub_id)

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = _override_current_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        trigger_resp = await client.post(
            f"/api/interactions/contracts/{fake_db.storage['contract'].id}/safe-mode",
            json={"reason": "overwhelmed", "duration_minutes": 20},
        )
        assert trigger_resp.status_code in {200, 409}

    app.dependency_overrides.clear()
