import importlib.util
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


def test_due_tokens_and_columns():
    title, date, time = planner.parse_due_tokens("GATE form due on @14-08-26 @@13:00")
    assert title == "GATE form due on"
    assert date == "2026-08-14"
    assert time == "13:00"
