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
