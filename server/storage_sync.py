"""Best-effort Azure Files backup for the single-replica SQLite deployment."""
from __future__ import annotations

import os
from pathlib import Path


def _client():
    connection_string = os.environ.get("STUDY_PLANNER_AZURE_STORAGE_CONNECTION_STRING", "")
    if not connection_string:
        return None
    from azure.storage.fileshare import ShareFileClient
    return ShareFileClient.from_connection_string(connection_string, share_name="planner-data", file_path="planner.db")


def restore() -> None:
    client = _client()
    if not client:
        return
    state_dir = Path(os.environ["STUDY_PLANNER_STATE_DIR"])
    state_dir.mkdir(parents=True, exist_ok=True)
    target = state_dir / "planner.db"
    try:
        content = client.download_file().readall()
        if content:
            target.write_bytes(content)
    except Exception:
        # A first deployment has no backup yet.
        return


def backup() -> None:
    client = _client()
    if not client:
        return
    database = Path(os.environ["STUDY_PLANNER_STATE_DIR"]) / "planner.db"
    if not database.is_file() or database.stat().st_size == 0:
        return
    try:
        with database.open("rb") as source:
            client.upload_file(source, overwrite=True)
    except Exception as exc:
        print(f"database backup failed: {exc}", flush=True)
