"""User authentication (signup, login, profile) and Bearer token verification."""
from __future__ import annotations

import hashlib
import secrets

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

from .config import get_settings
from .db import get_db, now_utc, seed_default_lists

_bearer = HTTPBearer(auto_error=False)
router = APIRouter(prefix="/auth", tags=["auth"])


def _hash_password(password: str, salt: str | None = None) -> str:
    salt = salt or secrets.token_hex(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), 100_000)
    return f"{salt}${dk.hex()}"


def _verify_password(password: str, stored: str) -> bool:
    try:
        salt, _ = stored.split("$", 1)
    except ValueError:
        return False
    return secrets.compare_digest(_hash_password(password, salt), stored)


def _default_profile_name(email: str) -> str:
    prefix = email.split("@", 1)[0].strip()
    return prefix or email.strip()


async def current_user_id(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    if creds is None or not creds.credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or missing API token")
    token = creds.credentials
    expected = get_settings().api_token
    if expected and secrets.compare_digest(token, expected):
        return "default"
    db = get_db()
    if db is not None:
        user = await db.users.find_one({"token": token})
        if user is not None:
            return str(user["_id"])
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or missing API token")


async def require_token(user_id: str = Depends(current_user_id)) -> str:
    return user_id


class AuthCredentials(BaseModel):
    email: str = Field(..., min_length=1, max_length=200)
    password: str = Field(..., min_length=1, max_length=200)


class ProfilePatch(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)


@router.post("/signup")
async def signup(body: AuthCredentials, db=Depends(get_db)):
    email = body.email.strip().lower()
    if not email:
        raise HTTPException(status_code=400, detail="Email or username is required")
    existing = await db.users.find_one({"email": email})
    if existing is not None:
        raise HTTPException(status_code=400, detail="Account already exists. Please log in.")
    name = _default_profile_name(body.email.strip())
    token = secrets.token_urlsafe(32)
    doc = {
        "email": email,
        "password_hash": _hash_password(body.password),
        "name": name,
        "token": token,
        "created_at": now_utc(),
    }
    res = await db.users.insert_one(doc)
    user_id = str(res.inserted_id)
    await seed_default_lists(db, user_id=user_id)
    return {"token": token, "email": email, "name": name}


@router.post("/login")
async def login(body: AuthCredentials, db=Depends(get_db)):
    email = body.email.strip().lower()
    user = await db.users.find_one({"email": email})
    if user is None or not _verify_password(body.password, user.get("password_hash", "")):
        raise HTTPException(status_code=401, detail="Invalid username/email or password")
    token = user.get("token") or secrets.token_urlsafe(32)
    name = user.get("name") or _default_profile_name(email)
    if token != user.get("token") or name != user.get("name"):
        await db.users.update_one({"_id": user["_id"]}, {"$set": {"token": token, "name": name}})
    user_id = str(user["_id"])
    if await db.lists.count_documents({"user_id": user_id}) == 0:
        await seed_default_lists(db, user_id=user_id)
    return {"token": token, "email": email, "name": name}


@router.patch("/profile")
async def update_profile(
    body: ProfilePatch,
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db=Depends(get_db),
):
    await current_user_id(creds)
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name cannot be empty")
    token = creds.credentials if creds else ""
    user = await db.users.find_one({"token": token})
    if user is not None:
        await db.users.update_one({"_id": user["_id"]}, {"$set": {"name": name}})
        return {"email": user["email"], "name": name}
    return {"email": "", "name": name}
