import time
from typing import Optional

_cache = {}

async def get_cached_url(short_code: str) -> Optional[str]:
    entry = _cache.get(f"url:{short_code}")
    if entry:
        value, ttl = entry
        if time.time() < ttl:
            return value
        else:
            del _cache[f"url:{short_code}"]
    return None

async def set_cached_url(short_code: str, original_url: str, ttl: int = 86400):
    _cache[f"url:{short_code}"] = (original_url, time.time() + ttl)

async def delete_cached_url(short_code: str):
    _cache.pop(f"url:{short_code}", None)

async def publish_click_event(short_code, ip, user_agent, referrer):
    pass