# Migration Baseline

This project now relies on schema objects that should be migrated in a controlled way
instead of relying only on `Base.metadata.create_all`.

## 1. Initialize Alembic (one-time)

Run from `backend/`:

```bash
alembic init migrations
```

Set the DB URL in `alembic.ini`:

```ini
sqlalchemy.url = postgresql+psycopg://postgres@db:5432/leashio
```

Update `migrations/env.py` to import your metadata:

```python
from app.db.models import Base

target_metadata = Base.metadata
```

## 2. Create a baseline revision

If this is a fresh deployment:

```bash
alembic revision --autogenerate -m "baseline schema"
alembic upgrade head
```

If production already has tables created by `create_all`, create an empty baseline and stamp:

```bash
alembic revision -m "baseline existing prod"
alembic stamp head
```

Then generate incremental migrations for all future changes:

```bash
alembic revision --autogenerate -m "describe change"
alembic upgrade head
```

## 3. Recommended rollout rule

Use one migration per feature branch and run `alembic upgrade head` in staging before
promoting backend image to production.
