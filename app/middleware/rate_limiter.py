import time
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from app.core.config import settings
_requests = {}
class RateLimiterMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path in ["/docs", "/openapi.json"]:
            return await call_next(request)
        user_id = getattr(request.state, "user_id", None)
        key = f"user:{user_id}" if user_id else f"ip:{request.client.host}"
        limit_str = settings.rate_limit_user if user_id else settings.rate_limit_anon
        max_req, window = limit_str.split("/")
        max_req = int(max_req)
        window_sec = {"second": 1, "minute": 60, "hour": 3600}.get(window, 60)
        now = time.time()
        if key not in _requests:
            _requests[key] = []
        _requests[key] = [t for t in _requests[key] if now - t < window_sec]
        if len(_requests[key]) >= max_req:
            raise HTTPException(status_code=429, detail="Too many requests")
        _requests[key].append(now)
        return await call_next(request)
