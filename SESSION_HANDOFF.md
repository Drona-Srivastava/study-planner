# Study Planner session handoff

This file is a handoff summary for continuing work on the Study Planner
Omarchy plugin. It is not a transcript of the chat session; the Codex chat
itself remains in the chat application. This file captures the project state,
decisions, commands, and recent changes so the work can continue from the
project directory.

## Project identity

- Name: `study-planner`
- Repository: `https://github.com/Drona-Srivastava/study-planner`
- Current latest commit: `6f340ca Add pointing cursor to interactive controls`
- Original working path: `/home/nova/Projects/Enhance Shihh/study-planner`
- Planned working path: `/home/nova/Projects/study-planner`
- Installed Omarchy path: `/home/nova/.config/omarchy/plugins/study-planner`
- Local database: `~/.local/state/omarchy/study-planner/planner.db`

## Current features

The plugin is a Quickshell/Omarchy bar widget, panel, and background service.
The panel has two tabs:

1. Agenda: current block, next block, and today's timetable.
2. Kanban: Backlog, In Progress, and Completed columns.

Tasks can be added from the Kanban tab. Each task can be moved with Start,
Complete, Reopen, and checklist controls. Drag and drop was deliberately
removed because it was unreliable in the Omarchy/Quickshell environment.

Due dates and times are entered through the task field. Typing `@` opens a
keyboard-navigable calendar, and typing `@@` opens a keyboard-navigable
24-hour time picker. Dates use `DD/MM/YY`; times use `HH:MM`.

The task card shows a relative value such as `Due in 1d 9h`. The due indicator
uses the active Omarchy accent color and a larger readable font.

The Agenda imports timetable class blocks and displays friendly names only:

- BCSE432E lab -> Drones Lab
- BCSE432E class -> RL Class
- BCSE301L -> SEO Class
- BCSE305L -> Embedded Class
- BCSE428P -> Drones Lab
- BCSE428L -> Drones Class

Generic `COLLEGE` campus-gap rows are excluded from the user-facing Agenda.

## Recent visual work

- Uses `Style.font.menuFamily` through the `uiFont` property.
- Uses Omarchy `Color` and `Style` values so themes continue to work.
- Added uppercase tab and column labels, clearer hierarchy, styled date and
  close controls, rounded surfaces, stronger borders, and a styled Add field.
- Reduced the panel to a maximum of 1060 by 640 pixels with larger margins.
- Added pointing-hand cursors to interactive custom areas, checkboxes, task
  buttons, calendar controls, and time-picker arrows.

## Component map

- `manifest.json`: Omarchy plugin metadata and entry points.
- `BarWidget.qml`: bar icon, tooltip, and panel toggle action.
- `PlannerPanel.qml`: full Agenda/Kanban UI, process calls, task actions,
  relative due-time display, calendar picker, and time picker.
- `PlannerService.qml`: periodic reminder process runner.
- `planner.py`: SQLite schema, timetable/document import, agenda calculation,
  task CRUD, task movement, block completion, reminder deduplication, and CLI.
- `data/Timetable.docx` and `data/Timetable.pdf`: timetable source documents.
- `tests/test_backend.py`: backend tests.
- `STUDY_PLANNER_DOCUMENTATION.docx`: detailed technical documentation.
- `README.txt`: short user-facing overview.

## Useful commands

Validate source:

  qmllint BarWidget.qml PlannerPanel.qml PlannerService.qml
  omarchy plugin validate .
  python3 -m unittest discover -s tests -v

Publish and apply a source update:

  git add <files>
  git commit -m "Description"
  git push origin main
  omarchy plugin update study-planner --yes
  omarchy restart shell

Inspect the database with the backend:

  python3 planner.py init
  python3 planner.py agenda
  python3 planner.py tasks
  python3 planner.py settings

## Important maintenance notes

- Do not edit `/usr/share/omarchy/`; it is managed by the Omarchy package.
- Keep the plugin's manifest entry points synchronized with actual filenames.
- Use `apply_patch` for source edits during Codex development.
- Preserve the local database when moving or updating the source directory.
- If the plugin stops opening after a source update, run the update command and
  then `omarchy restart shell`; check the Quickshell log for QML errors.
- The installed plugin is fetched from GitHub by Omarchy. Moving the local
  development directory does not change the installed copy until a new push
  and plugin update are performed.
