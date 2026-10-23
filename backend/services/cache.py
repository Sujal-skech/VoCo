"""
cache.py
Redis async client for session caching and wellness trend memoisation.
"""

import os
import json
import logging
from typing import Any, Optional

import redis.asyncio as aioredis

logger = logging.getLogger("voco.cache")

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")

_redis: Optional[aioredis.Redis] = None


async def init_redis() -> None:
    global _redis
    try:
        _redis = aioredis.from_url(REDIS_URL, encoding="utf-8", decode_responses=True)
        await _redis.ping()
        logger.info("Redis connected at %s", REDIS_URL)
    except Exception as exc:
        logger.warning("Redis unavailable (%s) — caching disabled.", exc)
        _redis = None


def _client() -> Optional[aioredis.Redis]:
    return _redis


async def set_json(key: str, value: Any, ttl_seconds: int = 300) -> None:
    if not _redis:
        return
    try:
        await _redis.setex(key, ttl_seconds, json.dumps(value))
    except Exception as exc:
        logger.debug("Cache set failed: %s", exc)


async def get_json(key: str) -> Optional[Any]:
    if not _redis:
        return None
    try:
        raw = await _redis.get(key)
        return json.loads(raw) if raw else None
    except Exception as exc:
        logger.debug("Cache get failed: %s", exc)
        return None


async def delete(key: str) -> None:
    if not _redis:
        return
    try:
        await _redis.delete(key)
    except Exception:
        pass
