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


settings = Settings()
