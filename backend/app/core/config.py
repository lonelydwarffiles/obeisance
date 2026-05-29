"""Application configuration."""

import os


class Settings:
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://postgres@db:5432/leashio",
    )
    btcpay_host: str = os.getenv("BTCPAY_HOST", "")
    btcpay_pem: str = os.getenv("BTCPAY_PEM", "")
    btcpay_api_token: str = os.getenv("BTCPAY_API_TOKEN", "")
    btcpay_webhook_secret: str = os.getenv("BTCPAY_WEBHOOK_SECRET", "")
    btcpay_store_id: str = os.getenv("BTCPAY_STORE_ID", "")
    lnd_rest_url: str = os.getenv("LND_REST_URL", "")
    lnd_macaroon: str = os.getenv("LND_MACAROON", "")
    lnd_cert_path: str = os.getenv("LND_CERT_PATH", "")
    lnd_fee_limit_sat: int = int(os.getenv("LND_FEE_LIMIT_SAT", "20"))
    base_platform_fee: float = float(os.getenv("BASE_PLATFORM_FEE", "19.00"))
    billing_grace_hours: int = int(os.getenv("BILLING_GRACE_HOURS", "48"))
    push_gateway_url: str = os.getenv("PUSH_GATEWAY_URL", "")
    push_gateway_token: str = os.getenv("PUSH_GATEWAY_TOKEN", "")


settings = Settings()
