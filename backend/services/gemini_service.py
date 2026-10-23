"""
gemini_service.py
Wraps Google Gemini 2.0 Flash SDK with VoCo-specific system context.
"""

import os
import logging
from functools import lru_cache

import google.generativeai as genai
from google.generativeai.types import HarmCategory, HarmBlockThreshold

logger = logging.getLogger("voco.gemini")

SYSTEM_PROMPT = """
You are VoCo AI, a supportive vocational assistant for visually impaired users.
Your responses must be:
- Concise (under 80 words) — they will be read aloud via text-to-speech.
- Clear and jargon-free.
- Encouraging and empowering.
- Directly actionable where possible.
Never use markdown formatting, bullet points, or special characters.
Always respond in plain conversational sentences.
"""

SAFETY_SETTINGS = {
    HarmCategory.HARM_CATEGORY_HATE_SPEECH:        HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
    HarmCategory.HARM_CATEGORY_HARASSMENT:         HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
    HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT:  HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
    HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT:  HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
}


@lru_cache(maxsize=1)
def _get_model() -> genai.GenerativeModel:
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        raise EnvironmentError("GEMINI_API_KEY environment variable is not set.")
    genai.configure(api_key=api_key)
    return genai.GenerativeModel(
        model_name="gemini-2.0-flash",
        system_instruction=SYSTEM_PROMPT,
        safety_settings=SAFETY_SETTINGS,
    )


async def generate_response(
    user_text: str,
    fatigue_index: float = 0.0,
    pitch_hz: float = 0.0,
) -> str:
    """
    Generate a TTS-optimised response from Gemini 2.0 Flash.
    Includes vocal health context so the AI can tailor advice.
    """
    context_prefix = ""
    if fatigue_index > 0.65:
        context_prefix = "[User appears vocally fatigued. Keep response extra short.] "
    elif pitch_hz > 0 and (pitch_hz < 80 or pitch_hz > 350):
        context_prefix = "[User's vocal pitch is outside normal range. Be supportive.] "

    prompt = f"{context_prefix}Visually impaired user query: {user_text}"

    try:
        model = _get_model()
        response = await model.generate_content_async(prompt)
        text = response.text.strip()
        # Strip any accidental markdown
        text = text.replace("**", "").replace("*", "").replace("#", "").replace("`", "")
        return text
    except EnvironmentError:
        logger.warning("Gemini API key not configured — returning fallback.")
        return (
            "I'm currently unable to connect to the AI service. "
            "Please check your internet connection and try again."
        )
    except Exception as exc:
        logger.error("Gemini error: %s", exc)
        return "I encountered an error processing your request. Please try again."
