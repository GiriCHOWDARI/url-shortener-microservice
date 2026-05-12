from fastapi import APIRouter, Depends, HTTPException, Request, Query
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timedelta
from jose import jwt, JWTError
from app.core.config import settings
from app.core.database import async_session
from app.models.user import User
from app.models.url import URL, URLStatus
from app.services.shortener import create_short_url
from app.services.cache import get_cached_url, set_cached_url, delete_cached_url, publish_click_event
from typing import Optional

# Router for /api endpoints (shortening, auth analytics, etc.)
router = APIRouter(prefix="/api", tags=["urls"])

# Separate router for the root-level redirect
redirect_router = APIRouter(tags=["redirect"])

async def get_db():
    async with async_session() as session:
        yield session

async def get_current_user(request: Request, db: AsyncSession = Depends(get_db)):
    auth = request.headers.get("Authorization")
    if not auth or not auth.startswith("Bearer "):
        return None
    token = auth.split(" ")[1]
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        user_id = int(payload.get("sub"))
        user = await db.get(User, user_id)
        if user:
            request.state.user_id = user.id
            return user
    except JWTError:
        pass
    return None

@router.post("/shorten")
async def shorten(
    request: Request,
    original_url: str = Query(...),
    custom_alias: Optional[str] = Query(None),
    expires_days: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user = Depends(get_current_user)
):
    if not original_url.startswith(("http://", "https://")):
        original_url = "https://" + original_url
    expires_at = datetime.utcnow() + timedelta(days=expires_days) if expires_days else None
    try:
        new_url = await create_short_url(
            db,
            original_url,
            user_id=current_user.id if current_user else None,
            custom_alias=custom_alias,
            expires_at=expires_at
        )
        await set_cached_url(new_url.short_code, new_url.original_url)
        return {
            "short_url": f"{request.base_url}{new_url.short_code}",
            "expires_at": new_url.expires_at
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

# 👇 This endpoint must be at the ROOT level, not under /api
@redirect_router.get("/{short_code}")
async def redirect_url(
    short_code: str,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    # Check cache first
    cached = await get_cached_url(short_code)
    if cached:
        # Publish click event asynchronously (no await, fire-and-forget in this light version)
        import asyncio
        asyncio.create_task(publish_click_event(
            short_code,
            request.client.host,
            request.headers.get("user-agent"),
            request.headers.get("referer")
        ))
        return RedirectResponse(cached)

    # Fallback to database
    result = await db.execute(select(URL).where(URL.short_code == short_code))
    url = result.scalar()
    if not url or url.status != URLStatus.active:
        raise HTTPException(status_code=404, detail="URL not found")
    if url.expires_at and url.expires_at < datetime.utcnow():
        url.status = URLStatus.expired
        await db.commit()
        raise HTTPException(status_code=410, detail="Link expired")

    # Cache it for next time
    await set_cached_url(short_code, url.original_url)

    # Fire-and-forget analytics
    import asyncio
    asyncio.create_task(publish_click_event(
        short_code,
        request.client.host,
        request.headers.get("user-agent"),
        request.headers.get("referer")
    ))

    return RedirectResponse(url.original_url)