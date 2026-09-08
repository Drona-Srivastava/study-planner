#!/usr/bin/env python3
"""SQLite backend for the study-planner Omarchy plugin."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sqlite3
import os
import subprocess
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


PLUGIN_DIR = Path(__file__).resolve().parent
STATE_DIR = Path(os.environ.get("STUDY_PLANNER_STATE_DIR", str(Path.home() / ".local" / "state" / "omarchy" / "study-planner")))
DB_PATH = STATE_DIR / "planner.db"
TZ_NAME = "Asia/Kolkata"
DAYS = {"MON": 0, "TUE": 1, "WED": 2, "THU": 3, "FRI": 4, "SAT": 5, "SUN": 6}
CATEGORIES = {"GATE", "DSA", "CLOUD", "CLASS", "COLLEGE", "REST", "TRAVEL", "SLEEP", "CONTEST", "REVIEW"}
ACTIONABLE = {"GATE", "DSA", "CLOUD", "CONTEST", "REVIEW", "COLLEGE"}
TIME_RE = re.compile(r"^(\d{1,2}:\d{2})\s*[–-]\s*(\d{1,2}:\d{2})$")


def emit(value: object) -> None:
    print(json.dumps(value, ensure_ascii=False))


def fail(message: str, code: int = 1) -> None:
    emit({"ok": False, "error": message})
    raise SystemExit(code)


def connect() -> sqlite3.Connection:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(STATE_DIR / "planner.db")
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    return con


def init_db(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS schedule_blocks (
            id INTEGER PRIMARY KEY,
            weekday INTEGER NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT 'timetable',
            UNIQUE(weekday, start_time, end_time, title)
        );
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY,
            event_date TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            title TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'CONTEST',
            UNIQUE(event_date, start_time, title)
        );
        CREATE TABLE IF NOT EXISTS block_instances (
            instance_date TEXT NOT NULL,
            block_id INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            updated_at TEXT NOT NULL,
            PRIMARY KEY(instance_date, block_id),
            FOREIGN KEY(block_id) REFERENCES schedule_blocks(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            details TEXT NOT NULL DEFAULT '',
            column_name TEXT NOT NULL DEFAULT 'Backlog',
            category TEXT NOT NULL DEFAULT '',
            due_date TEXT NOT NULL DEFAULT '',
            due_time TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            completed_at TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS notification_log (
            notification_key TEXT PRIMARY KEY,
            sent_at TEXT NOT NULL
        );
        """
    )
    defaults = {
        "timezone": TZ_NAME,
        "lead_minutes": "10",
        "notify_at_start": "1",
        "notify_missed": "0",
    }
    con.executemany("INSERT OR IGNORE INTO settings(key, value) VALUES (?, ?)", defaults.items())
    columns = {row["name"] for row in con.execute("PRAGMA table_info(tasks)")}
    if "due_time" not in columns:
        con.execute("ALTER TABLE tasks ADD COLUMN due_time TEXT NOT NULL DEFAULT ''")
    con.execute("UPDATE tasks SET column_name='In Progress' WHERE column_name='To Do'")
    con.commit()


def clean_lines(path: Path) -> list[str]:
    if path.suffix.lower() == ".docx":
        with zipfile.ZipFile(path) as archive:
            root = ET.fromstring(archive.read("word/document.xml"))
        ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
        result = []
        for paragraph in root.findall(".//w:p", ns):
            result.append("".join(node.text or "" for node in paragraph.findall(".//w:t", ns)).strip())
        return result
    try:
        return subprocess.check_output(["pdftotext", "-layout", str(path), "-"], text=True).splitlines()
    except (FileNotFoundError, subprocess.CalledProcessError):
        return []


def parse_timetable(path: Path) -> list[dict[str, object]]:
    lines = [re.sub(r"\s+", " ", line.strip()) for line in clean_lines(path)]
    blocks: list[dict[str, object]] = []
    current_day: int | None = None
    i = 0
    while i < len(lines):
        line = lines[i].upper()
        if line in DAYS:
            current_day = DAYS[line]
            i += 1
            continue
        match = TIME_RE.match(lines[i])
        if current_day is None or not match:
            i += 1
            continue
        start, end = match.groups()
        j = i + 1
        parts: list[str] = []
        category = ""
        while j < len(lines) and j < i + 8:
            candidate = lines[j].strip()
            upper = candidate.upper()
            if TIME_RE.match(candidate) or upper in DAYS:
                break
            if upper in CATEGORIES:
                category = upper
                break
            if candidate and candidate not in {"Time", "Activity", "Category"}:
                parts.append(candidate)
            j += 1
        if category in ACTIONABLE | {"REST", "TRAVEL", "SLEEP", "CLASS"} and parts:
            title = " ".join(parts).replace("  ", " ")
            blocks.append({"weekday": current_day, "start": start, "end": end, "title": title, "category": category})
        i = max(i + 1, j + 1)
    return blocks


def parse_contest_events(path: Path) -> list[dict[str, str]]:
    text = "\n".join(clean_lines(path))
    events = []
    patterns = [
        (r"Biweekly Contest \d+ on [A-Za-z]+ (\d{1,2}) Sep (\d{4})", "20:00", "21:30", "LeetCode Biweekly Contest"),
        (r"Weekly Contest \d+ on [A-Za-z]+ (\d{1,2}) Sep (\d{4})", "08:00", "09:30", "LeetCode Weekly Contest"),
    ]
    for pattern, start, end, title in patterns:
        for day, year in re.findall(pattern, text, flags=re.IGNORECASE):
            events.append({"date": f"{year}-09-{int(day):02d}", "start": start, "end": end, "title": title})
    return events


def import_documents(con: sqlite3.Connection) -> tuple[int, int]:
    docx = PLUGIN_DIR / "data" / "Timetable.docx"
    pdf = PLUGIN_DIR / "data" / "Timetable.pdf"
    source = docx if docx.exists() else pdf
    if not source.exists():
        fail("No timetable source document found")
    blocks = parse_timetable(source)
    # Keep the importer useful even when a future Word export changes table spacing.
    if not blocks:
        fail("Could not extract weekly timetable rows from the source document")
    for block in blocks:
        con.execute(
            "INSERT OR IGNORE INTO schedule_blocks(weekday,start_time,end_time,title,category) VALUES(?,?,?,?,?)",
            (block["weekday"], block["start"], block["end"], block["title"], block["category"]),
        )
    event_count = 0
    for event in parse_contest_events(pdf if pdf.exists() else source):
        cur = con.execute(
            "INSERT OR IGNORE INTO events(event_date,start_time,end_time,title) VALUES(?,?,?,?)",
            (event["date"], event["start"], event["end"], event["title"]),
        )
        event_count += cur.rowcount
    con.execute("INSERT OR REPLACE INTO settings(key,value) VALUES('source_hash',?)", (hashlib.sha256(source.read_bytes()).hexdigest(),))
    con.commit()
    return len(blocks), event_count


def ensure_ready(con: sqlite3.Connection) -> None:
    init_db(con)
    count = con.execute("SELECT COUNT(*) FROM schedule_blocks").fetchone()[0]
    if count == 0:
        import_documents(con)


def now() -> dt.datetime:
    return dt.datetime.now().astimezone()


def iso_now() -> str:
    return now().isoformat(timespec="seconds")


def agenda(con: sqlite3.Connection, date: dt.date | None = None) -> dict[str, object]:
    date = date or now().date()
    weekday = date.weekday()
    rows = con.execute(
        "SELECT b.*, COALESCE(i.status,'pending') status FROM schedule_blocks b LEFT JOIN block_instances i ON i.block_id=b.id AND i.instance_date=? WHERE b.weekday=? AND b.category IN ('GATE','DSA','CLOUD','CONTEST','REVIEW','COLLEGE') ORDER BY b.start_time",
        (date.isoformat(), weekday),
    ).fetchall()
    items = [dict(row) for row in rows]
    event_rows = con.execute("SELECT id,start_time,end_time,title,category FROM events WHERE event_date=? ORDER BY start_time", (date.isoformat(),)).fetchall()
    for event in event_rows:
        items.append({"id": -event["id"], "start_time": event["start_time"], "end_time": event["end_time"], "title": event["title"], "category": event["category"], "status": "pending", "event": True})
    items.sort(key=lambda x: x["start_time"])
    current_minutes = now().hour * 60 + now().minute
    current = None
    upcoming = None
    for item in items:
        start = int(item["start_time"][:2]) * 60 + int(item["start_time"][3:])
        end = int(item["end_time"][:2]) * 60 + int(item["end_time"][3:])
        if item["status"] == "completed":
            continue
        if start <= current_minutes < end:
            current = item
        elif start > current_minutes and upcoming is None:
            upcoming = item
        elif current_minutes >= end and item["status"] == "pending":
            item["status"] = "missed"
    return {"date": date.isoformat(), "items": items, "current": current, "next": upcoming}


def due_notifications(con: sqlite3.Connection) -> list[dict[str, str]]:
    plan = agenda(con)
    now_minutes = now().hour * 60 + now().minute
    lead = int(con.execute("SELECT value FROM settings WHERE key='lead_minutes'").fetchone()[0])
    at_start = con.execute("SELECT value FROM settings WHERE key='notify_at_start'").fetchone()[0] == "1"
    notify_missed = con.execute("SELECT value FROM settings WHERE key='notify_missed'").fetchone()[0] == "1"
    output = []
    for item in plan["items"]:
        if item.get("status") == "completed":
            continue
        start = int(item["start_time"][:2]) * 60 + int(item["start_time"][3:])
        end = int(item["end_time"][:2]) * 60 + int(item["end_time"][3:])
        key_base = f"{plan['date']}:{item['id']}"
        kind = ""
        headline = ""
        description = ""
        if start - lead <= now_minutes < start and lead >= 0:
            kind = "lead"
            headline = f"Starting in {max(1, start - now_minutes)} min: {item['title']}"
            description = f"{item['category']} · {item['start_time']}–{item['end_time']}"
        elif at_start and start <= now_minutes < end:
            kind = "start"
            headline = f"Now: {item['title']}"
            description = f"{item['category']} · {item['start_time']}–{item['end_time']}"
        elif notify_missed and now_minutes >= end and item.get("status") == "missed":
            kind = "missed"
            headline = f"Missed: {item['title']}"
            description = f"Scheduled {item['start_time']}–{item['end_time']}"
        if not kind:
            continue
        key = key_base + ":" + kind
        exists = con.execute("SELECT 1 FROM notification_log WHERE notification_key=?", (key,)).fetchone()
        if exists:
            continue
        con.execute("INSERT INTO notification_log(notification_key,sent_at) VALUES(?,?)", (key, iso_now()))
        output.append({"key": key, "headline": headline, "description": description})
    con.commit()
    return output


def tasks(con: sqlite3.Connection) -> list[dict[str, object]]:
    return [dict(row) for row in con.execute("SELECT * FROM tasks ORDER BY CASE column_name WHEN 'Backlog' THEN 0 WHEN 'In Progress' THEN 1 ELSE 2 END, id DESC")]


def parse_due_tokens(title: str, due_date: str = "", due_time: str = "") -> tuple[str, str, str]:
    due_date = re.sub(r"^@\{?", "", due_date.strip())
    due_date = re.sub(r"\}?$", "", due_date)
    due_time = re.sub(r"^@@\{?", "", due_time.strip())
    due_time = re.sub(r"\}?$", "", due_time)
    time_match = re.search(r"@@\{?([01]?\d|2[0-3]):([0-5]\d)\}?", title)
    date_match = re.search(r"(?<!@)@\{?(\d{1,2}[-/]\d{1,2}[-/](?:\d{2}|\d{4})|\d{4}-\d{2}-\d{2})\}?", title)
    if not due_time and time_match:
        due_time = f"{int(time_match.group(1)):02d}:{time_match.group(2)}"
    raw_date = due_date or (date_match.group(1) if date_match else "")
    if raw_date:
        try:
            if raw_date.count("-") == 2 and len(raw_date.split("-")[0]) == 4:
                parsed = dt.datetime.strptime(raw_date, "%Y-%m-%d")
            else:
                year_length = len(re.split(r"[-/]", raw_date)[-1])
                parsed = dt.datetime.strptime(raw_date.replace("/", "-"), "%d-%m-%y" if year_length == 2 else "%d-%m-%Y")
            due_date = parsed.date().isoformat()
        except ValueError:
            fail("Due date must use DD/MM/YY")
    if due_time:
        try:
            due_time = dt.datetime.strptime(due_time, "%H:%M").strftime("%H:%M")
        except ValueError:
            fail("Due time must use HH:MM")
    title = re.sub(r"@@\{?(?:[01]?\d|2[0-3]):[0-5]\d\}?", "", title)
    title = re.sub(r"(?<!@)@\{?(?:\d{1,2}[-/]\d{1,2}[-/](?:\d{2}|\d{4})|\d{4}-\d{2}-\d{2})\}?", "", title)
    return re.sub(r"\s+", " ", title).strip(), due_date, due_time


def command(args: argparse.Namespace) -> None:
    con = connect()
    init_db(con)
    if args.action == "init":
        count, events = import_documents(con) if con.execute("SELECT COUNT(*) FROM schedule_blocks").fetchone()[0] == 0 else (con.execute("SELECT COUNT(*) FROM schedule_blocks").fetchone()[0], 0)
        emit({"ok": True, "database": str(DB_PATH), "blocks": count, "events": events})
    elif args.action == "agenda":
        ensure_ready(con)
        emit({"ok": True, **agenda(con)})
    elif args.action == "tasks":
        ensure_ready(con)
        emit({"ok": True, "tasks": tasks(con)})
    elif args.action == "stats":
        ensure_ready(con)
        counts = {row["column_name"]: row["count"] for row in con.execute("SELECT column_name,COUNT(*) count FROM tasks GROUP BY column_name")}
        emit({"ok": True, "backlog": counts.get("Backlog", 0), "in_progress": counts.get("In Progress", 0), "todo": counts.get("In Progress", 0), "completed": counts.get("Completed", 0), "remaining": counts.get("Backlog", 0) + counts.get("In Progress", 0)})
    elif args.action == "settings":
        if args.key and args.value is not None:
            allowed = {"lead_minutes", "notify_at_start", "notify_missed"}
            if args.key not in allowed:
                fail("Unknown setting")
            if args.key == "lead_minutes" and (not args.value.isdigit() or int(args.value) < 0 or int(args.value) > 180):
                fail("lead_minutes must be between 0 and 180")
            if args.key != "lead_minutes" and args.value not in {"0", "1"}:
                fail(f"{args.key} must be 0 or 1")
            con.execute("INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)", (args.key, args.value)); con.commit()
        values = {row["key"]: row["value"] for row in con.execute("SELECT key,value FROM settings WHERE key IN ('timezone','lead_minutes','notify_at_start','notify_missed')")}
        emit({"ok": True, "settings": values})
    elif args.action == "add":
        title, due_date, due_time = parse_due_tokens(args.title, args.due or "", args.due_time or "")
        if not title:
            fail("Task title cannot be empty")
        column = {"To Do": "In Progress"}.get(args.column or "Backlog", args.column or "Backlog")
        if column not in {"Backlog", "In Progress", "Completed"}:
            fail("Invalid column")
        con.execute("INSERT INTO tasks(title,details,column_name,category,due_date,due_time,created_at) VALUES(?,?,?,?,?,?,?)", (title, args.details or "", column, args.category or "", due_date, due_time, iso_now()))
        con.commit(); emit({"ok": True})
    elif args.action == "move":
        column = {"To Do": "In Progress"}.get(args.column, args.column)
        if column not in {"Backlog", "In Progress", "Completed"}: fail("Invalid column")
        con.execute("UPDATE tasks SET column_name=?, completed_at=? WHERE id=?", (column, iso_now() if column == "Completed" else "", args.id)); con.commit(); emit({"ok": True})
    elif args.action == "delete":
        con.execute("DELETE FROM tasks WHERE id=?", (args.id,)); con.commit(); emit({"ok": True})
    elif args.action == "complete-block":
        if args.id > 0:
            con.execute("INSERT INTO block_instances(instance_date,block_id,status,updated_at) VALUES(?,?,?,?) ON CONFLICT(instance_date,block_id) DO UPDATE SET status=excluded.status,updated_at=excluded.updated_at", (now().date().isoformat(), args.id, "completed", iso_now())); con.commit()
        emit({"ok": True})
    elif args.action == "reminders":
        ensure_ready(con)
        notifications = due_notifications(con)
        if os.environ.get("STUDY_PLANNER_NO_NOTIFY") != "1":
            for notification in notifications:
                try:
                    subprocess.run(["omarchy", "notification", "send", "--app-name", "study-planner", notification["headline"], notification["description"]], check=False, timeout=5)
                except (FileNotFoundError, subprocess.TimeoutExpired):
                    pass
        emit({"ok": True, "notifications": notifications, "agenda": agenda(con)})
    con.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("init"); sub.add_parser("agenda"); sub.add_parser("tasks"); sub.add_parser("stats"); sub.add_parser("reminders")
    settings = sub.add_parser("settings"); settings.add_argument("key", nargs="?"); settings.add_argument("value", nargs="?")
    add = sub.add_parser("add"); add.add_argument("title"); add.add_argument("--details"); add.add_argument("--column", default="Backlog"); add.add_argument("--category"); add.add_argument("--due"); add.add_argument("--due-time")
    move = sub.add_parser("move"); move.add_argument("id", type=int); move.add_argument("column")
    delete = sub.add_parser("delete"); delete.add_argument("id", type=int)
    complete = sub.add_parser("complete-block"); complete.add_argument("id", type=int)
    try: command(parser.parse_args())
    except sqlite3.Error as exc: fail(f"Database error: {exc}")


if __name__ == "__main__":
    main()
