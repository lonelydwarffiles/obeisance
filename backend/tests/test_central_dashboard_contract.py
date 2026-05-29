from __future__ import annotations

from datetime import date, datetime, timezone
from types import SimpleNamespace

import pytest
from httpx import ASGITransport, AsyncClient

from app.api.dependencies import require_superadmin
from app.db.database import get_db
from app.main import app


class _ScalarProxy:
    def __init__(self, values):
        self._values = values

    def all(self):
        return self._values


class _ExecuteResult:
    def __init__(self, *, scalar_value=None, scalar_values=None, rows=None):
        self._scalar_value = scalar_value
        self._scalar_values = scalar_values or []
        self._rows = rows or []

    def scalar_one(self):
        return self._scalar_value

    def scalars(self):
        return _ScalarProxy(self._scalar_values)

    def all(self):
        return self._rows


class _SummarySession:
    def __init__(self):
        self._calls = 0

    async def execute(self, _statement):
        self._calls += 1
        mapping = {
            1: _ExecuteResult(scalar_value=42),
            2: _ExecuteResult(scalar_value=18),
            3: _ExecuteResult(scalar_value=5),
            4: _ExecuteResult(scalar_value=19),
            5: _ExecuteResult(scalar_value=12),
            6: _ExecuteResult(scalar_value=3),
            7: _ExecuteResult(scalar_value=4),
            8: _ExecuteResult(scalar_value=2),
            9: _ExecuteResult(scalar_value=7),
            10: _ExecuteResult(scalar_values=["dom_a", "dom_b"]),
            11: _ExecuteResult(
                scalar_values=[
                    SimpleNamespace(
                        action="billing_cycle_paid",
                        target_type="billing_cycle",
                        created_at=datetime(2026, 5, 28, tzinfo=timezone.utc),
                    )
                ]
            ),
        }
        return mapping[self._calls]


class _TrendSession:
    def __init__(self):
        self._calls = 0

    async def execute(self, statement):
        self._calls += 1
        if self._calls == 1:
            return _ExecuteResult(rows=[(date(2026, 5, 27), 2), (date(2026, 5, 28), 3)])
        return _ExecuteResult(rows=[(date(2026, 5, 27), 1), (date(2026, 5, 28), 4)])


class _DrilldownSession:
    async def execute(self, statement):
        sql_text = str(statement)
        now = datetime(2026, 5, 28, 12, 0, tzinfo=timezone.utc)
        if "FROM petitions" in sql_text:
            petition = SimpleNamespace(
                id="petition-id",
                dom_id="dom-id",
                package_name="com.example.app",
                reason="Need temporary access",
                created_at=now,
            )
            return _ExecuteResult(rows=[(petition, "dom_a")])
        if "billing_cycles" in sql_text and "count" in sql_text.lower():
            return _ExecuteResult(rows=[("dom-id", "dom_a", 3, now)])
        return _ExecuteResult(
            scalar_values=[
                SimpleNamespace(
                    id="dom-id",
                    username="dom_a",
                    billing_renewal_date=now,
                )
            ]
        )


async def _override_superadmin():
    return SimpleNamespace(id="superadmin-id")


@pytest.mark.asyncio
async def test_central_summary_contract_shape() -> None:
    async def _override_db():
        yield _SummarySession()

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[require_superadmin] = _override_superadmin

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.get("/api/central/dashboard-summary")

    assert response.status_code == 200
    payload = response.json()
    assert payload["total_devices"] == 42
    assert payload["open_petitions"] == 7
    assert payload["overdue_doms"] == ["dom_a", "dom_b"]
    assert len(payload["recent_audit_events"]) == 1

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_central_trends_contract_shape() -> None:
    async def _override_db():
        yield _TrendSession()

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[require_superadmin] = _override_superadmin

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.get("/api/central/trends?days=2")

    assert response.status_code == 200
    payload = response.json()
    assert "points" in payload
    assert len(payload["points"]) == 2
    petition_counts = [point["open_petitions"] for point in payload["points"]]
    assert 4 in petition_counts

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_central_drilldown_contract_shape() -> None:
    async def _override_db():
        yield _DrilldownSession()

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[require_superadmin] = _override_superadmin

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        open_petitions = await client.get("/api/central/drilldown/open-petitions")
        overdue_doms = await client.get("/api/central/drilldown/overdue-doms")
        inactive_doms = await client.get("/api/central/drilldown/inactive-doms")

    assert open_petitions.status_code == 200
    assert overdue_doms.status_code == 200
    assert inactive_doms.status_code == 200
    assert open_petitions.json()["petitions"][0]["dom_username"] == "dom_a"
    assert overdue_doms.json()["doms"][0]["overdue_cycle_count"] == 3
    assert inactive_doms.json()["doms"][0]["username"] == "dom_a"

    app.dependency_overrides.clear()
