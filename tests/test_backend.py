import importlib.util
import datetime as dt
import tempfile
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("planner", Path(__file__).parents[1] / "planner.py")
planner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(planner)


def test_docx_import_has_actionable_blocks():
    blocks = planner.parse_timetable(Path(__file__).parents[1] / "data" / "Timetable.docx")
    assert blocks
    assert {row["category"] for row in blocks} >= {"GATE", "DSA", "CLOUD"}
    assert all(row["weekday"] in range(7) for row in blocks)


def test_agenda_includes_all_non_meal_timetable_items():
    with tempfile.TemporaryDirectory() as directory:
        old = planner.STATE_DIR
        planner.STATE_DIR = Path(directory)
        con = planner.connect()
        planner.init_db(con)
        rows = [
            (0, "07:00", "07:30", "Wake + hygiene", "REST"),
            (0, "07:30", "08:00", "Breakfast", "REST"),
            (0, "08:00", "10:00", "GATE study", "GATE"),
            (0, "10:00", "10:30", "Break", "REST"),
            (0, "15:50", "16:40", "RL Class", "CLASS"),
            (0, "18:00", "19:00", "Dinner + decompression", "REST"),
            (0, "20:00", "21:30", "Competition", "CONTEST"),
        ]
        con.executemany(
            "INSERT INTO schedule_blocks(weekday,start_time,end_time,title,category) VALUES(?,?,?,?,?)",
            rows,
        )
        con.commit()
        result = planner.agenda(con, dt.date(2026, 9, 14))
        titles = [item["title"] for item in result["items"]]
        assert titles == ["Wake + hygiene", "GATE study", "Break", "RL Class", "Competition"]
        con.close()
        planner.STATE_DIR = old


def test_database_and_tasks():
    with tempfile.TemporaryDirectory() as directory:
        old = planner.STATE_DIR
        planner.STATE_DIR = Path(directory)
        con = planner.connect()
        planner.init_db(con)
        con.execute("INSERT INTO tasks(title,created_at) VALUES (?,?)", ("Solve arrays", planner.iso_now()))
        con.commit()
        assert planner.tasks(con)[0]["title"] == "Solve arrays"
        con.execute("UPDATE tasks SET column_name='To Do'")
        con.commit()
        planner.init_db(con)
        assert planner.tasks(con)[0]["column_name"] == "In Progress"
        con.close()
        planner.STATE_DIR = old


def test_kanban_reminder_defaults_to_30_minutes():
    with tempfile.TemporaryDirectory() as directory:
        old = planner.STATE_DIR
        planner.STATE_DIR = Path(directory)
        con = planner.connect()
        planner.init_db(con)
        value = con.execute(
            "SELECT value FROM settings WHERE key='kanban_reminder_minutes'"
        ).fetchone()[0]
        assert value == "30"
        assert con.execute(
            "SELECT 1 FROM settings WHERE key='kanban_reminder_hours'"
        ).fetchone() is None
        con.close()
        planner.STATE_DIR = old


def test_due_tokens_and_columns():
    title, date, time = planner.parse_due_tokens("GATE form due on @14-08-26 @@13:00")
    assert title == "GATE form due on"
    assert date == "2026-08-14"
    assert time == "13:00"
