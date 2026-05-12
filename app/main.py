from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from app.middleware.rate_limiter import RateLimiterMiddleware
from app.api import auth, urls
from app.core.database import engine, Base

app = FastAPI(title="URL Shortener", docs_url="/docs")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.add_middleware(RateLimiterMiddleware)

# API routes (auth, URL shortening)
app.include_router(auth.router)
app.include_router(urls.router)

# 👇 Redirect route – must be added BEFORE the static mount and WITHOUT a prefix
app.include_router(urls.redirect_router)

@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

# Static files (UI) – mounted last so it doesn't steal dynamic routes
app.mount("/", StaticFiles(directory="app/static", html=True), name="static")