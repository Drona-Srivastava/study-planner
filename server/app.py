"""Small HTTP API and static PWA host for Study Planner."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
from datetime import date
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

import planner


WEB_DIR = Path(__file__).resolve().parents[1] / "web"
SESSION_SECRET = os.environ.get("STUDY_PLANNER_SESSION_SECRET", "change-me-in-production").encode()
USERNAME = os.environ.get("STUDY_PLANNER_USERNAME", "planner")
PASSWORD = os.environ.get("STUDY_PLANNER_PASSWORD", "")
VAPID_PUBLIC_KEY = os.environ.get("STUDY_PLANNER_VAPID_PUBLIC_KEY", "")

app = FastAPI(title="Study Planner API", version="1.0")
allowed_origins = [item.strip() for item in os.environ.get("STUDY_PLANNER_ALLOWED_ORIGINS", "").split(",") if item.strip()]
allowed_origin_regex = os.environ.get("STUDY_PLANNER_ALLOWED_ORIGIN_REGEX", "")
if allowed_origins or allowed_origin_regex:
    app.add_middleware(CORSMiddleware, allow_origins=allowed_origins, allow_origin_regex=allowed_origin_regex or None, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.mount("/static", StaticFiles(directory=WEB_DIR), name="static")


class Login(BaseModel):
    username: str
    password: str


class TaskInput(BaseModel):
    title: str = Field(min_length=1, max_length=500)
    details: str = ""
    column: str = "Backlog"
    category: str = ""
    due: str = ""
    due_time: str = ""


class TaskMove(BaseModel):
    column: str


class PushSubscription(BaseModel):
    endpoint: str
    keys: dict[str, str]


def token_for(username: str) -> str:
    expiry = str(int(time.time()) + 60 * 60 * 24 * 30)
    payload = f"{username}:{expiry}".encode()
    signature = hmac.new(SESSION_SECRET, payload, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(payload + b":" + signature).decode()


def current_user(request: Request) -> str:
    token = request.cookies.get("study_planner_session", "")
    try:
        raw = base64.urlsafe_b64decode(token.encode())
        username, expiry, signature = raw.split(b":", 2)
        payload = username + b":" + expiry
        valid = hmac.compare_digest(signature, hmac.new(SESSION_SECRET, payload, hashlib.sha256).digest())
        if not valid or int(expiry) < int(time.time()) or username.decode() != USERNAME:
            raise ValueError
        return username.decode()
    except (ValueError, TypeError, UnicodeDecodeError, base64.Error):
        raise HTTPException(status_code=401, detail="Login required")


def db():
    con = planner.connect()
    try:
        yield con
    finally:
        con.close()


@app.get("/")
def home() -> FileResponse:
    return FileResponse(WEB_DIR / "index.html")


@app.get("/health")
def health() -> dict[str, bool]:
    return {"ok": True}


@app.post("/auth/login")
def login(credentials: Login, response: Response) -> dict[str, bool]:
    if not PASSWORD or not hmac.compare_digest(credentials.username, USERNAME) or not hmac.compare_digest(credentials.password, PASSWORD):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    secure_cookie = os.environ.get("STUDY_PLANNER_COOKIE_SECURE", "1") == "1"
    response.set_cookie("study_planner_session", token_for(USERNAME), httponly=True, secure=secure_cookie, samesite="lax", max_age=60 * 60 * 24 * 30)
    return {"ok": True}


@app.post("/auth/logout")
def logout(response: Response, _: str = Depends(current_user)) -> dict[str, bool]:
    response.delete_cookie("study_planner_session")
    return {"ok": True}


@app.get("/api/config")
def config(_: str = Depends(current_user)) -> dict[str, str]:
    return {"vapid_public_key": VAPID_PUBLIC_KEY, "timezone": planner.TZ_NAME}


@app.get("/api/agenda")
def agenda(day: str | None = None, _: str = Depends(current_user), con=Depends(db)) -> dict[str, Any]:
    try:
        selected = date.fromisoformat(day) if day else None
    except ValueError:
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")
    return planner.agenda(con, selected)


@app.get("/api/tasks")
def get_tasks(_: str = Depends(current_user), con=Depends(db)) -> dict[str, Any]:
    return {"tasks": planner.tasks(con)}


@app.post("/api/tasks")
def add_task(task: TaskInput, _: str = Depends(current_user), con=Depends(db)) -> dict[str, bool]:
    title, due_date, due_time = planner.parse_due_tokens(task.title, task.due, task.due_time)
    if not title:
        raise HTTPException(status_code=400, detail="Task title cannot be empty")
    column = {"To Do": "In Progress"}.get(task.column, task.column)
    if column not in {"Backlog", "In Progress", "Completed"}:
        raise HTTPException(status_code=400, detail="Invalid column")
    con.execute("INSERT INTO tasks(title,details,column_name,category,due_date,due_time,created_at) VALUES(?,?,?,?,?,?,?)", (title, task.details, column, task.category, due_date, due_time, planner.iso_now()))
    con.commit()
    return {"ok": True}


@app.patch("/api/tasks/{task_id}")
def move_task(task_id: int, move: TaskMove, _: str = Depends(current_user), con=Depends(db)) -> dict[str, bool]:
    column = {"To Do": "In Progress"}.get(move.column, move.column)
    if column not in {"Backlog", "In Progress", "Completed"}:
        raise HTTPException(status_code=400, detail="Invalid column")
    con.execute("UPDATE tasks SET column_name=?, completed_at=? WHERE id=?", (column, planner.iso_now() if column == "Completed" else "", task_id))
    con.commit()
    return {"ok": True}


@app.delete("/api/tasks/{task_id}")
def delete_task(task_id: int, _: str = Depends(current_user), con=Depends(db)) -> dict[str, bool]:
    con.execute("DELETE FROM tasks WHERE id=?", (task_id,)); con.commit()
    return {"ok": True}


@app.post("/api/push/subscribe")
def subscribe(subscription: PushSubscription, _: str = Depends(current_user), con=Depends(db)) -> dict[str, bool]:
    con.execute("CREATE TABLE IF NOT EXISTS push_subscriptions(endpoint TEXT PRIMARY KEY, subscription_json TEXT NOT NULL, created_at TEXT NOT NULL)")
    con.execute("INSERT OR REPLACE INTO push_subscriptions VALUES(?,?,?)", (subscription.endpoint, json.dumps(subscription.model_dump()), planner.iso_now()))
    con.commit()
    return {"ok": True}


@app.delete("/api/push/subscribe")
def unsubscribe(subscription: PushSubscription, _: str = Depends(current_user), con=Depends(db)) -> dict[str, bool]:
    con.execute("DELETE FROM push_subscriptions WHERE endpoint=?", (subscription.endpoint,)); con.commit()
    return {"ok": True}


# Keep this catch-all mount after the API routes so it cannot shadow them.
app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="pwa")
