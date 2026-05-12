# setup.ps1 - Creates the entire URL Shortener project (no Docker required)
$root = 'D:\url-shortener'
$dirs = 'app\api','app\core','app\middleware','app\models','app\services','app\utils','app\static','docker','tests','migrations'
$dirs | % { New-Item -ItemType Directory -Path (Join-Path $root $_) -Force | Out-Null }

# requirements.txt
@'
fastapi==0.115.6
uvicorn[standard]==0.34.0
sqlalchemy[asyncio]==2.0.36
aiosqlite==0.20.0
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
pydantic-settings==2.7.1
python-multipart==0.0.18
'@ | Set-Content -Path "$root\requirements.txt"

# .env
@'
DATABASE_URL=sqlite+aiosqlite:///./shortener.db
SECRET_KEY=change-me-to-a-random-string-123!@#
ACCESS_TOKEN_EXPIRE_MINUTES=30
RATE_LIMIT_ANON=10/minute
RATE_LIMIT_USER=100/minute
CACHE_TTL_SECONDS=86400
'@ | Set-Content -Path "$root\.env"

# app\core\config.py
@'
from pydantic_settings import BaseSettings
class Settings(BaseSettings):
    database_url: str = "sqlite+aiosqlite:///./shortener.db"
    secret_key: str = "dev-secret"
    access_token_expire_minutes: int = 30
    rate_limit_anon: str = "10/minute"
    rate_limit_user: str = "100/minute"
    cache_ttl_seconds: int = 86400
    class Config:
        env_file = ".env"
settings = Settings()
'@ | Set-Content -Path "$root\app\core\config.py"

# app\core\database.py
@'
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from .config import settings
engine = create_async_engine(settings.database_url, echo=False)
async_session = async_sessionmaker(engine, expire_on_commit=False)
class Base(DeclarativeBase):
    pass
'@ | Set-Content -Path "$root\app\core\database.py"

# app\core\security.py
@'
from datetime import datetime, timedelta
from jose import jwt
from passlib.context import CryptContext
from .config import settings
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
def hash_password(password: str) -> str:
    return pwd_context.hash(password)
def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)
def create_access_token(data: dict) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.access_token_expire_minutes)
    to_encode = data.copy()
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.secret_key, algorithm="HS256")
'@ | Set-Content -Path "$root\app\core\security.py"

# app\models\user.py
@'
from sqlalchemy import Column, Integer, String
from app.core.database import Base
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
'@ | Set-Content -Path "$root\app\models\user.py"

# app\models\url.py
@'
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Enum
from sqlalchemy.orm import relationship
import enum
from app.core.database import Base
class URLStatus(str, enum.Enum):
    active = "active"
    expired = "expired"
    disabled = "disabled"
class URL(Base):
    __tablename__ = "urls"
    id = Column(Integer, primary_key=True, index=True)
    original_url = Column(String, nullable=False)
    short_code = Column(String, unique=True, index=True, nullable=False)
    created_at = Column(DateTime, nullable=False)
    expires_at = Column(DateTime, nullable=True)
    status = Column(Enum(URLStatus), default=URLStatus.active)
    click_count = Column(Integer, default=0)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    owner = relationship("User")
'@ | Set-Content -Path "$root\app\models\url.py"

# app\models\analytics.py
@'
from sqlalchemy import Column, Integer, String, DateTime
from app.core.database import Base
class ClickEvent(Base):
    __tablename__ = "click_events"
    id = Column(Integer, primary_key=True, index=True)
    short_code = Column(String, index=True, nullable=False)
    timestamp = Column(DateTime, nullable=False)
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)
    referrer = Column(String, nullable=True)
'@ | Set-Content -Path "$root\app\models\analytics.py"

# app\services\shortener.py
@'
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
'@ | Set-Content -Path "$root\app\services\shortener.py"

# app\services\cache.py
@'
import time, asyncio
_cache = {}
async def get_cached_url(short_code: str):
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
'@ | Set-Content -Path "$root\app\services\cache.py"

# app\middleware\rate_limiter.py
@'
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
'@ | Set-Content -Path "$root\app\middleware\rate_limiter.py"

# app\api\auth.py
@'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import async_session
from app.core.security import hash_password, verify_password, create_access_token
from app.models.user import User
from pydantic import BaseModel, EmailStr
router = APIRouter(prefix="/auth", tags=["auth"])
class UserCreate(BaseModel):
    username: str
    email: EmailStr
    password: str
class UserLogin(BaseModel):
    email: EmailStr
    password: str
async def get_db():
    async with async_session() as session:
        yield session
@router.post("/register")
async def register(user: UserCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where((User.email == user.email) | (User.username == user.username)))
    if result.scalar():
        raise HTTPException(status_code=400, detail="User already exists")
    new_user = User(username=user.username, email=user.email, password_hash=hash_password(user.password))
    db.add(new_user)
    await db.commit()
    return {"message": "User created"}
@router.post("/login")
async def login(login_data: UserLogin, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == login_data.email))
    user = result.scalar()
    if not user or not verify_password(login_data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = create_access_token({"sub": str(user.id)})
    return {"access_token": token, "token_type": "bearer"}
'@ | Set-Content -Path "$root\app\api\auth.py"

# app\api\urls.py
@'
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timedelta
from jose import jwt, JWTError
from app.core.config import settings
from app.models.user import User
from app.models.url import URL, URLStatus
from app.services.shortener import create_short_url
from app.services.cache import get_cached_url, set_cached_url, delete_cached_url, publish_click_event
from typing import Optional
router = APIRouter(prefix="/api", tags=["urls"])
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
async def shorten(request: Request, original_url: str = Query(...), custom_alias: Optional[str] = Query(None), expires_days: Optional[int] = Query(None), db: AsyncSession = Depends(get_db), current_user = Depends(get_current_user)):
    if not original_url.startswith(("http://", "https://")):
        original_url = "https://" + original_url
    expires_at = datetime.utcnow() + timedelta(days=expires_days) if expires_days else None
    try:
        new_url = await create_short_url(db, original_url, user_id=current_user.id if current_user else None, custom_alias=custom_alias, expires_at=expires_at)
        await set_cached_url(new_url.short_code, new_url.original_url)
        return {"short_url": f"{request.base_url}{new_url.short_code}", "expires_at": new_url.expires_at}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
@router.get("/{short_code}")
async def redirect_url(short_code: str, request: Request, db: AsyncSession = Depends(get_db)):
    cached = await get_cached_url(short_code)
    if cached:
        await publish_click_event(short_code, request.client.host, request.headers.get("user-agent"), request.headers.get("referer"))
        return RedirectResponse(cached)
    result = await db.execute(select(URL).where(URL.short_code == short_code))
    url = result.scalar()
    if not url or url.status != URLStatus.active:
        raise HTTPException(status_code=404, detail="URL not found")
    if url.expires_at and url.expires_at < datetime.utcnow():
        url.status = URLStatus.expired
        await db.commit()
        raise HTTPException(status_code=410, detail="Link expired")
    await set_cached_url(short_code, url.original_url)
    await publish_click_event(short_code, request.client.host, request.headers.get("user-agent"), request.headers.get("referer"))
    return RedirectResponse(url.original_url)
'@ | Set-Content -Path "$root\app\api\urls.py"

# app\main.py
@'
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from app.middleware.rate_limiter import RateLimiterMiddleware
from app.api import auth, urls
from app.core.database import engine, Base
app = FastAPI(title="URL Shortener", docs_url="/docs")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.add_middleware(RateLimiterMiddleware)
app.include_router(auth.router)
app.include_router(urls.router)
@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
app.mount("/", StaticFiles(directory="app/static", html=True), name="static")
'@ | Set-Content -Path "$root\app\main.py"

# app\static\index.html
@'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ShortLink</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <div class="container">
    <h1>✂️ ShortLink</h1>
    <p>Paste a long URL and get a short, shareable link.</p>
    <div class="form-group">
      <input type="url" id="originalUrl" placeholder="https://example.com/very-long-url...">
      <input type="text" id="alias" placeholder="Custom alias (optional)" maxlength="20">
      <input type="number" id="expiry" placeholder="Expire in days (optional)" min="1">
      <button id="shortenBtn">Shorten</button>
    </div>
    <div id="result" class="result-box hidden"></div>
    <div class="footer">Built with FastAPI</div>
  </div>
  <script src="/script.js"></script>
</body>
</html>
'@ | Set-Content -Path "$root\app\static\index.html"

# app\static\style.css
@'
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: "Segoe UI", sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh; display: flex; justify-content: center; align-items: center;
}
.container {
  background: white; border-radius: 20px; padding: 2.5rem;
  box-shadow: 0 20px 40px rgba(0,0,0,0.2); width: 90%; max-width: 500px; text-align: center;
}
h1 { font-size: 2.5rem; margin-bottom: 0.5rem; }
p { color: #666; margin-bottom: 2rem; }
.form-group { display: flex; flex-direction: column; gap: 1rem; }
input {
  padding: 14px; border: 2px solid #e0e0e0; border-radius: 10px; font-size: 1rem;
  transition: border 0.2s;
}
input:focus { border-color: #667eea; outline: none; }
button {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white; border: none; padding: 14px; border-radius: 10px; font-size: 1.1rem;
  cursor: pointer; transition: transform 0.2s, box-shadow 0.2s;
}
button:hover { transform: translateY(-2px); box-shadow: 0 5px 15px rgba(102,126,234,0.4); }
.result-box {
  margin-top: 2rem; background: #f0f0f0; padding: 1rem; border-radius: 10px;
  word-break: break-all; display: flex; justify-content: space-between; align-items: center;
}
.result-box a { color: #667eea; text-decoration: none; }
.copy-btn { background: #667eea; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; }
.hidden { display: none; }
.footer { margin-top: 2rem; color: #aaa; font-size: 0.8rem; }
'@ | Set-Content -Path "$root\app\static\style.css"

# app\static\script.js
@'
document.getElementById("shortenBtn").addEventListener("click", async () => {
    const original = document.getElementById("originalUrl").value.trim();
    const alias = document.getElementById("alias").value.trim();
    const expiry = document.getElementById("expiry").value.trim();
    if (!original) return alert("Please enter a URL");
    let apiUrl = `/api/shorten?original_url=${encodeURIComponent(original)}`;
    if (alias) apiUrl += `&custom_alias=${encodeURIComponent(alias)}`;
    if (expiry) apiUrl += `&expires_days=${encodeURIComponent(expiry)}`;
    try {
        const token = localStorage.getItem("token") || "";
        const res = await fetch(apiUrl, {
            method: "POST",
            headers: { "Authorization": `Bearer ${token}` }
        });
        if (!res.ok) {
            const err = await res.json();
            throw new Error(err.detail || "Failed");
        }
        const data = await res.json();
        const div = document.getElementById("result");
        div.classList.remove("hidden");
        div.innerHTML = `<a href="${data.short_url}" target="_blank">${data.short_url}</a><button class="copy-btn" onclick="copyToClipboard('${data.short_url}')">Copy</button>`;
    } catch (e) {
        alert(`Error: ${e.message}`);
    }
});

function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => alert("Copied!"))
        .catch(() => prompt("Copy manually:", text));
}
'@ | Set-Content -Path "$root\app\static\script.js"

Write-Host "✅ Project files created successfully!"