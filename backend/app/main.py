from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes.billing import router as billing_router
from app.api.routes.candidate import router as candidate_router
from app.api.routes.device import router as device_router
from app.api.routes.library import router as library_router
from app.api.routes.notes import router as notes_router
from app.api.routes.staging import router as staging_router
from app.api.routes.store import router as store_router
from app.api.routes.submission import router as submission_router


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
app.include_router(library_router, prefix="/api")
app.include_router(notes_router, prefix="/api")
app.include_router(staging_router, prefix="/api")
app.include_router(store_router, prefix="/api")
app.include_router(submission_router, prefix="/api")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
