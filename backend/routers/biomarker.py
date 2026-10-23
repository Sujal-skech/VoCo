"""
biomarker.py
Ingest and query vocal biomarker telemetry.
"""

from datetime import datetime
from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
import logging

from services.database import get_db
from models.biomarker_model import BiomarkerReading

logger = logging.getLogger("voco.biomarker")
router = APIRouter()


# MARK: - Schemas

class BiomarkerIngestRequest(BaseModel):
    user_id: str = Field(..., min_length=1, max_length=256)
    pitch_hz: float = Field(default=0.0, ge=0.0)
    jitter_percent: float = Field(default=0.0, ge=0.0, le=100.0)
    shimmer_percent: float = Field(default=0.0, ge=0.0, le=100.0)
    fatigue_index: float = Field(default=0.0, ge=0.0, le=1.0)
    wellness_score: float = Field(default=0.0, ge=0.0, le=100.0)
    timestamp: str | None = None


class BiomarkerSummary(BaseModel):
    user_id: str
    total_readings: int
    avg_wellness: float
    avg_fatigue: float
    avg_pitch_hz: float


# MARK: - Endpoints

@router.post("/ingest", status_code=status.HTTP_204_NO_CONTENT)
async def ingest_biomarker(
    req: BiomarkerIngestRequest,
    db: AsyncSession = Depends(get_db),
) -> None:
    """Persist a single biomarker snapshot from the iOS device."""
    recorded_at = datetime.utcnow()
    if req.timestamp:
        try:
            from datetime import timezone
            recorded_at = datetime.fromisoformat(req.timestamp.replace("Z", "+00:00"))
        except ValueError:
            pass  # fall back to utcnow

    reading = BiomarkerReading(
        user_id=req.user_id,
        pitch_hz=req.pitch_hz,
        jitter_percent=req.jitter_percent,
        shimmer_percent=req.shimmer_percent,
        fatigue_index=req.fatigue_index,
        wellness_score=req.wellness_score,
        recorded_at=recorded_at,
    )
    db.add(reading)
    logger.debug("Ingested biomarker for user %s — wellness=%.1f", req.user_id, req.wellness_score)


@router.get("/summary/{user_id}", response_model=BiomarkerSummary)
async def get_summary(
    user_id: str,
    db: AsyncSession = Depends(get_db),
) -> BiomarkerSummary:
    """Aggregate statistics for a user."""
    result = await db.execute(
        select(
            func.count(BiomarkerReading.id),
            func.avg(BiomarkerReading.wellness_score),
            func.avg(BiomarkerReading.fatigue_index),
            func.avg(BiomarkerReading.pitch_hz),
        ).where(BiomarkerReading.user_id == user_id)
    )
    row = result.one()
    count, avg_well, avg_fat, avg_pitch = row

    return BiomarkerSummary(
        user_id=user_id,
        total_readings=count or 0,
        avg_wellness=round(avg_well or 0.0, 1),
        avg_fatigue=round(avg_fat or 0.0, 3),
        avg_pitch_hz=round(avg_pitch or 0.0, 1),
    )
