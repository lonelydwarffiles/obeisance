import pytest
from httpx import ASGITransport, AsyncClient

from app.api.dependencies import hash_api_key
from app.main import app


@pytest.mark.asyncio
async def test_health_returns_ok_and_request_id_header() -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        response = await client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert response.headers.get("X-Request-Id")


def test_hash_api_key_is_stable() -> None:
    left = hash_api_key("sample-key")
    right = hash_api_key("sample-key")
    other = hash_api_key("another-key")

    assert left == right
    assert left != other
    assert len(left) == 64
