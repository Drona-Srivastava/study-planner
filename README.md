# Study Planner

An Omarchy plugin for a GATE/placement timetable, reminders, and a separate
SQLite Kanban board.

## Install

After publishing this folder to GitHub:

```bash
omarchy plugin add https://github.com/YOUR-USER/study-planner.git --enable
```

The plugin adds the widget to the default bar section. Click it to open the
Agenda and Kanban panel. The timetable documents are imported on first run.

## Storage

The database is stored at:

```text
~/.local/state/omarchy/study-planner/planner.db
```

Timetable blocks and daily completion history are separate from manual tasks.
Manual tasks use `Backlog`, `In Progress`, and `Completed` columns. Existing
`To Do` values are migrated to `In Progress` automatically.

### Due dates and times

Tasks accept either or both of these tokens in the title:

```text
GATE form due on @14/08/26 @@13:00
```

Type `@` in the task title to open the calendar picker. Type `@@` to open the
24-hour time picker. Dates are displayed and entered as `DD/MM/YY`; times use
24-hour `HH:MM` format. Existing hyphenated dates remain readable and are
normalized when saved.

Cards can be dragged between columns. Each card also has a checklist control,
a `Start` action for moving Backlog to In Progress, and Complete/Reopen actions.

## Reminder settings

The defaults are a 10-minute reminder and a start-time reminder. Missed-block
notifications are disabled by default. They can be changed with:

```bash
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings lead_minutes 15
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings notify_at_start 0
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings notify_missed 1
```

## Development validation

```bash
omarchy plugin validate .
qmllint BarWidget.qml PlannerPanel.qml PlannerService.qml
STUDY_PLANNER_STATE_DIR=/tmp/study-planner-test python3 planner.py init
```
