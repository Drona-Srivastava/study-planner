"""Server-side reminder loop. Run as a separate container/process."""
from __future__ import annotations

import json
import os
import sqlite3
import time

import planner
from server.storage_sync import backup


def send(notification: dict[str, str], subscription: dict[str, str]) -> None:
    try:
        from pywebpush import webpush
        webpush(subscription_info=subscription, data=json.dumps(notification), vapid_private_key=os.environ["STUDY_PLANNER_VAPID_PRIVATE_KEY"], vapid_claims={"sub": os.environ.get("STUDY_PLANNER_VAPID_SUBJECT", "mailto:planner@example.com")})
    except Exception as exc:
        print(f"push delivery failed: {exc}", flush=True)


def main() -> None:
    while True:
        try:
            con = planner.connect()
            try:
                notifications = planner.due_notifications(con)
                rows = con.execute("SELECT endpoint,subscription_json FROM push_subscriptions").fetchall()
                for item in notifications:
                    for row in rows:
                        send(item, json.loads(row["subscription_json"]))
            finally:
                con.close()
        except sqlite3.OperationalError as exc:
            if "locked" not in str(exc).lower():
                print(f"worker database error: {exc}", flush=True)
            else:
                print("worker waiting for database lock", flush=True)
        else:
            backup()
        time.sleep(30)


if __name__ == "__main__":
    main()
