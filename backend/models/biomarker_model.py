"""
biomarker_model.py
SQLAlchemy ORM model for persisted vocal biomarker readings.
"""

from datetime import datetime
from sqlalchemy import String, Float, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column

from services.database import Base


class BiomarkerReading(Base):
    __tablename__ = "biomarker_readings"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(128), index=True, nullable=False)
    pitch_hz: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    jitter_percent: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    shimmer_percent: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    fatigue_index: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    wellness_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
