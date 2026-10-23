"""
voice.py
Voice command router — classifies intent locally, falls back to Gemini.
"""

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field
import logging

from services.gemini_service import generate_response
from services import cache

logger = logging.getLogger("voco.voice")
router = APIRouter()


# MARK: - Request / Response Schemas

class VoiceRequest(BaseModel):
    user_id: str = Field(..., min_length=1, max_length=256)
    transcribed_text: str = Field(..., min_length=1, max_length=2000)
    fatigue_index: float = Field(default=0.0, ge=0.0, le=1.0)
    pitch_hz: float = Field(default=0.0, ge=0.0)


class VoiceResponse(BaseModel):
    action: str           # NAVIGATE | SPEAK_AI | WELLNESS_ALERT
    route: str
    speak: str
    data: dict | None = None


# MARK: - Intent Rules

_NAV_INTENTS: dict[str, tuple[str, str]] = {
    "pronunciation":  ("PronunciationView",  "Opening Pronunciation Training."),
    "pronounce":      ("PronunciationView",  "Opening Pronunciation Training."),
    "talk":           ("AssistantView",      "VoCo AI Assistant is active."),
    "assistant":      ("AssistantView",      "VoCo AI Assistant is active."),
    "chat":           ("AssistantView",      "VoCo AI Assistant is active."),
    "wellness":       ("WellnessView",       "Opening your wellness dashboard."),
    "health":         ("WellnessView",       "Opening your wellness dashboard."),
    "fatigue":        ("WellnessView",       "Opening your wellness dashboard."),
    "jobs":           ("JobsView",           "Opening job opportunities."),
    "career":         ("JobsView",           "Opening job opportunities."),
    "work":           ("JobsView",           "Opening job opportunities."),
    "settings":       ("SettingsView",       "Opening settings."),
    "preferences":    ("SettingsView",       "Opening settings."),
    "dashboard":      ("DashboardView",      "Returning to dashboard."),
    "home":           ("DashboardView",      "Returning to dashboard."),
}


# MARK: - Router Endpoint

@router.post("/router", response_model=VoiceResponse, status_code=status.HTTP_200_OK)
async def route_command(req: VoiceRequest) -> VoiceResponse:
    """
    Primary voice command endpoint.
    1. Check local navigation intent map.
    2. Check for wellness alert shortcut.
    3. Fall through to Gemini for open queries.
    """
    text = req.transcribed_text.lower().strip()

    # 1. Navigation intent
    for keyword, (route, speak) in _NAV_INTENTS.items():
        if keyword in text:
            logger.info("NAV intent '%s' → %s for user %s", keyword, route, req.user_id)
            return VoiceResponse(action="NAVIGATE", route=route, speak=speak)

    # 2. Wellness alert (high fatigue)
    if req.fatigue_index > 0.75:
        msg = (
            "Your vocal fatigue is very high. "
            "I recommend a 5-minute break before continuing. "
            "Drink some water and rest your voice."
        )
        return VoiceResponse(
            action="WELLNESS_ALERT",
            route="WellnessView",
            speak=msg,
            data={"fatigue_index": str(req.fatigue_index)},
        )

    # 3. Gemini AI response
    logger.info("AI query from user %s: %s", req.user_id, req.transcribed_text[:80])

    # Cache key: avoid identical repeated calls
    cache_key = f"gemini:{req.user_id}:{hash(req.transcribed_text)}"
    cached = await cache.get_json(cache_key)
    if cached:
        return VoiceResponse(action="SPEAK_AI", route="Current", speak=cached["speak"])

    ai_text = await generate_response(
        req.transcribed_text,
        fatigue_index=req.fatigue_index,
        pitch_hz=req.pitch_hz,
    )
    await cache.set_json(cache_key, {"speak": ai_text}, ttl_seconds=120)

    return VoiceResponse(action="SPEAK_AI", route="Current", speak=ai_text)
