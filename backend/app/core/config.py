"""Application configuration."""

import os


class Settings:
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://postgres@db:5432/leashio",
    )


settings = Settings()
