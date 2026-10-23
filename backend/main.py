"""
VoCo Backend Engine
FastAPI service: voice command routing, Gemini 2.0 Flash AI, biomarker telemetry, wellness trends.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging

from routers import voice, biomarker, wellness
from services.database import init_db
from services.cache import init_redis

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger("voco")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup / shutdown lifecycle."""
    logger.info("VoCo backend starting…")
    await init_db()
    await init_redis()
    yield
    logger.info("VoCo backend shutting down.")


app = FastAPI(
    title="VoCo Backend Engine",
    description="Voice-Powered Vocational Training API for Visually Impaired Users",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # tighten to app bundle ID in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers
app.include_router(voice.router,      prefix="/api/v1/voice",      tags=["Voice"])
app.include_router(biomarker.router,  prefix="/api/v1/biomarker",  tags=["Biomarker"])
app.include_router(wellness.router,   prefix="/api/v1/wellness",   tags=["Wellness"])


@app.get("/health", tags=["System"])
async def health_check():
    return {"status": "healthy", "service": "VoCo Backend Engine"}
