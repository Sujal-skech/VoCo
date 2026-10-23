"""
wellness.py
Cognitive wellness trends and personalised recommendations.
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc
import logging

from services.database import get_db
from services import cache
from models.biomarker_model import BiomarkerReading

logger = logging.getLogger("voco.wellness")
router = APIRouter()


# MARK: - Response Schema

class WellnessTrend(BaseModel):
    user_id: str
    average_wellness: float
    session_count: int
    trend_direction: str    # "improving" | "stable" | "declining"
    recommendation: str


# MARK: - Recommendation Engine

_RECOMMENDATIONS = {
    "high_fatigue": (
        "Your vocal fatigue has been elevated recently. "
        "Try scheduling regular 10-minute rest breaks between training sessions."
    ),
    "improving": (
        "Your wellness is improving. Keep up the great work! "
        "Try the advanced pronunciation module when you feel ready."
    ),
    "stable": (
        "Your wellness is stable. "
        "Consider adding a daily 5-minute breathing warm-up before sessions."
    ),
    "declining": (
        "Your wellness score has dipped recently. "
        "Rest your voice, stay hydrated, and reduce session length for a day or two."
    ),
    "new_user": (
        "Welcome to VoCo! Complete your first pronunciation module to start building your wellness profile."
    ),
}


# MARK: - Trend Endpoint

@router.get("/trend/{user_id}", response_model=WellnessTrend)
async def get_wellness_trend(
    user_id: str,
    db: AsyncSession = Depends(get_db),
) -> WellnessTrend:
    """Return a wellness trend summary with personalised recommendation."""

    cache_key = f"wellness_trend:{user_id}"
    cached = await cache.get_json(cache_key)
    if cached:
        return WellnessTrend(**cached)

    # Last 50 readings for this user, newest first
    result = await db.execute(
        select(BiomarkerReading.wellness_score, BiomarkerReading.fatigue_index)
        .where(BiomarkerReading.user_id == user_id)
        .order_by(desc(BiomarkerReading.recorded_at))
        .limit(50)
    )
    rows = result.all()

    if not rows:
        trend = WellnessTrend(
            user_id=user_id,
            average_wellness=0.0,
            session_count=0,
            trend_direction="stable",
            recommendation=_RECOMMENDATIONS["new_user"],
        )
        return trend

    scores = [r.wellness_score for r in rows]
    fatigue_vals = [r.fatigue_index for r in rows]
    avg_wellness = sum(scores) / len(scores)
    avg_fatigue = sum(fatigue_vals) / len(fatigue_vals)

    # Trend: compare first half vs second half (oldest half = recent in desc order)
    half = len(scores) // 2 or 1
    recent_avg = sum(scores[:half]) / half
    older_avg = sum(scores[half:]) / max(len(scores[half:]), 1)

    if recent_avg > older_avg + 3:
        direction = "improving"
        rec = _RECOMMENDATIONS["improving"]
    elif recent_avg < older_avg - 3:
        direction = "declining"
        rec = _RECOMMENDATIONS["declining"]
    else:
        direction = "stable"
        rec = _RECOMMENDATIONS["stable"]

    if avg_fatigue > 0.65:
        rec = _RECOMMENDATIONS["high_fatigue"]

    trend = WellnessTrend(
        user_id=user_id,
        average_wellness=round(avg_wellness, 1),
        session_count=len(rows),
        trend_direction=direction,
        recommendation=rec,
    )

    await cache.set_json(cache_key, trend.model_dump(), ttl_seconds=180)
    logger.info("Wellness trend computed for user %s: %s (%.1f)", user_id, direction, avg_wellness)
    return trend
