from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes.billing import router as billing_router
from app.api.routes.candidate import router as candidate_router
from app.api.routes.device import router as device_router
from app.api.routes.dynamic import router as dynamic_router
from app.api.routes.growth import router as growth_router
from app.api.routes.ledger import router as ledger_router
from app.api.routes.library import router as library_router
from app.api.routes.metrics import router as metrics_router
from app.api.routes.notes import router as notes_router
from app.api.routes.staging import router as staging_router
from app.api.routes.store import router as store_router
from app.api.routes.submission import router as submission_router
from app.api.routes.webhooks import router as webhooks_router
from app.core.scheduler import scheduler
from app.db.database import init_db


app = FastAPI(title="Leashio MDM API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(billing_router, prefix="/api")
app.include_router(candidate_router, prefix="/api")
app.include_router(device_router, prefix="/api")
app.include_router(dynamic_router, prefix="/api")
app.include_router(growth_router, prefix="/api")
app.include_router(ledger_router, prefix="/api")
app.include_router(library_router, prefix="/api")
app.include_router(metrics_router, prefix="/api")
app.include_router(notes_router, prefix="/api")
app.include_router(staging_router, prefix="/api")
app.include_router(store_router, prefix="/api")
app.include_router(submission_router, prefix="/api")
app.include_router(webhooks_router, prefix="/api")


@app.on_event("startup")
async def on_startup() -> None:
    await init_db()
    if not scheduler.running:
        scheduler.start()


@app.on_event("shutdown")
async def on_shutdown() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
