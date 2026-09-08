STUDY PLANNER
=============

Study Planner is an Omarchy shell plugin for managing a GATE and placement
study timetable alongside a local Kanban task board.

WHAT IT DOES
------------

• Shows today's timetable and the next/current scheduled block.
• Sends reminder notifications for timetable blocks through Omarchy.
• Provides Backlog, In Progress, and Completed task columns.
• Lets each task have an optional due date, due time, or both.
• Opens a calendar when @ is typed and a 24-hour time picker when @@ is typed.
• Stores all user data locally in SQLite; no cloud service is required.
• Uses the timetable documents in data/ as the import source.

INSTALL
-------

Install directly from GitHub:

  omarchy plugin add https://github.com/Drona-Srivastava/study-planner.git --enable

For an existing installation, update it with:

  omarchy plugin update study-planner --yes
  omarchy restart shell

The plugin adds a Study Planner icon to the Omarchy bar. Click it to open the
panel. Escape or the close button dismisses the panel.

DATA LOCATION
-------------

The SQLite database is stored at:

  ~/.local/state/omarchy/study-planner/planner.db

The installed plugin is normally stored at:

  ~/.config/omarchy/plugins/study-planner

The source repository is:

  https://github.com/Drona-Srivastava/study-planner

DOCUMENTATION
-------------

STUDY_PLANNER_DOCUMENTATION.docx contains the detailed component-by-component
technical guide. SESSION_HANDOFF.md records the development history and the
current state of this session for future work.

DEVELOPMENT
-----------

From this directory:

  qmllint BarWidget.qml PlannerPanel.qml PlannerService.qml
  omarchy plugin validate .
  python3 -m unittest discover -s tests -v

The plugin intentionally uses the active Omarchy theme and menu font instead
of hardcoding a specific font or color palette.
