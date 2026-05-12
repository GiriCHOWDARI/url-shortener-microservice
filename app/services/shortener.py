import hashlib, base64, re
from datetime import datetime
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.url import URL, URLStatus
def _generate_short_code(original_url: str, length: int = 7) -> str:
    hash_bytes = hashlib.sha256(original_url.encode()).digest()
    return base64.urlsafe_b64encode(hash_bytes).decode()[:length]
async def create_short_url(db: AsyncSession, original_url: str, user_id: int = None, custom_alias: str = None, expires_at: datetime = None) -> URL:
    if custom_alias:
        if not re.match(r"^[a-zA-Z0-9\-]{5,20}$", custom_alias):
            raise ValueError("Alias must be 5-20 chars, alphanumeric/hyphen")
        existing = await db.execute(select(URL).where(URL.short_code == custom_alias))
        if existing.scalar():
            raise ValueError("Alias already taken")
        short_code = custom_alias
    else:
        short_code = _generate_short_code(original_url)
        for _ in range(5):
            exists = await db.execute(select(URL).where(URL.short_code == short_code))
            if exists.scalar() is None:
                break
            short_code = _generate_short_code(original_url + str(datetime.utcnow().timestamp()))
        else:
            raise RuntimeError("Could not generate unique code")
    url = URL(original_url=original_url, short_code=short_code, created_at=datetime.utcnow(), expires_at=expires_at, user_id=user_id)
    db.add(url)
    await db.commit()
    await db.refresh(url)
    return url
