#!/usr/bin/env python3
"""Export the local planner database into a portable JSON migration file."""
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import planner

con = planner.connect(); planner.init_db(con)
tables = {"settings", "schedule_blocks", "events", "block_instances", "tasks"}
data = {}
for table in tables:
    data[table] = [dict(row) for row in con.execute(f"SELECT * FROM {table}")]
print(json.dumps(data, ensure_ascii=False, indent=2))
con.close()
