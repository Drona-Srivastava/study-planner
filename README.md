# Study Planner

An Omarchy plugin for a GATE/placement timetable, reminders, and a separate
SQLite Kanban board.

## Install

After publishing this folder to GitHub:

```bash
omarchy plugin add https://github.com/Drona-Srivastava/study-planner --enable
```

The plugin adds the widget to the default bar section. Click it to open the
Agenda and Kanban panel. The timetable documents are imported on first run.

## Storage

The database is stored at:

```text
~/.local/state/omarchy/study-planner/planner.db
```

The Agenda shows every timetable activity and competition except breakfast,
lunch, and dinner rows. Timetable blocks and daily completion history are
separate from manual tasks.
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

The board is arranged in three columns. Each card has a checklist control, a
`Start` action for moving Backlog to In Progress, and Complete/Reopen actions.

## Reminder settings

The defaults are a 10-minute reminder, a start-time reminder, and a Kanban
check reminder every 4 hours. Agenda and Kanban notifications play the
standard system sound at `/usr/share/sounds/freedesktop/stereo/message-new-instant.oga`
when available. Missed-block notifications are disabled by default. They can
be changed with:

```bash
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings lead_minutes 15
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings notify_at_start 0
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings notify_missed 1
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings kanban_reminder_hours 4
```

Set `STUDY_PLANNER_SOUND_FILE` to choose another local sound, or
`STUDY_PLANNER_NO_SOUND=1` to disable sounds.

## Development validation

```bash
omarchy plugin validate .
qmllint BarWidget.qml PlannerPanel.qml PlannerService.qml
STUDY_PLANNER_STATE_DIR=/tmp/study-planner-test python3 planner.py init
```
