"""Run the API and reminder worker in one low-cost Container App replica."""
from __future__ import annotations

import subprocess
import sys
import time

import uvicorn
import planner
from server.storage_sync import restore


restore()
for attempt in range(10):
    try:
        con = planner.connect()
        planner.ensure_ready(con)
        con.close()
        break
    except Exception:
        if attempt == 9:
            raise
        time.sleep(3)

worker = subprocess.Popen([sys.executable, "-m", "server.worker"])
try:
    uvicorn.run("server.app:app", host="0.0.0.0", port=8000)
finally:
    worker.terminate()
    worker.wait(timeout=10)
