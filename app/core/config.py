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
