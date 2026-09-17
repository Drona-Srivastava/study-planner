#!/usr/bin/env python3
"""Import a JSON file produced by export_data.py into the cloud database."""
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import planner

if len(sys.argv) != 2:
    raise SystemExit("usage: import_data.py migration.json")
data = json.load(open(sys.argv[1], encoding="utf-8"))
con = planner.connect(); planner.init_db(con)
for table in ("settings", "schedule_blocks", "events", "block_instances", "tasks"):
    rows = data.get(table, [])
    if not rows:
        continue
    columns = list(rows[0])
    marks = ",".join("?" for _ in columns)
    con.executemany(f"INSERT OR REPLACE INTO {table} ({','.join(columns)}) VALUES ({marks})", [[row.get(c) for c in columns] for row in rows])
con.commit(); con.close()
print("Imported planner data")
