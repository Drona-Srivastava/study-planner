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
check reminder every 30 minutes. The first Kanban reminder is scheduled 30
minutes after the plugin service starts, then repeats every 30 minutes without
duplicating reminders during the 30-second polling loop. Agenda and Kanban
notifications play the standard system sound at
`/usr/share/sounds/freedesktop/stereo/message-new-instant.oga` when available;
the plugin uses `pw-play` or `paplay` to play it. Missed-block notifications
are disabled by default. They can be changed with:

```bash
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings lead_minutes 15
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings notify_at_start 0
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings notify_missed 1
python3 ~/.config/omarchy/plugins/study-planner/planner.py settings kanban_reminder_minutes 30
```

Set `STUDY_PLANNER_SOUND_FILE` to choose another local sound, or
`STUDY_PLANNER_NO_SOUND=1` to disable sounds.

## Development validation

```bash
omarchy plugin validate .
qmllint BarWidget.qml PlannerPanel.qml PlannerService.qml
STUDY_PLANNER_STATE_DIR=/tmp/study-planner-test python3 planner.py init

## iPhone PWA and Web Push

The repository also includes a mobile PWA and a cloud API. The API and worker
share a SQLite volume; the worker sends agenda and task due-time notifications
to subscribed Home Screen web apps.

Deploy with Docker on a VPS whose DNS points to the server:

```bash
cp .env.example .env
# Set the domain, long password, session secret, and VAPID keys in .env.
docker compose up -d --build
```

To migrate the existing desktop database before starting the worker:

```bash
STUDY_PLANNER_STATE_DIR=~/.local/state/omarchy/study-planner \
  python3 tools/export_data.py > migration.json
docker compose cp migration.json api:/tmp/migration.json
docker compose exec api python tools/import_data.py /tmp/migration.json
rm migration.json
```

The `STUDY_PLANNER_VAPID_PUBLIC_KEY` and private key must be generated as a
matching pair using the `py-vapid` tooling or another Web Push VAPID utility.
Never commit `.env` or the private key. Caddy
provides HTTPS automatically once the domain resolves. On the iPhone, open the
HTTPS URL in Safari, use Share → Add to Home Screen, sign in, and tap Enable
notifications. Web Push is supported for Home Screen web apps on iOS 16.4+.

### Split deployment: Vercel frontend

In Vercel, import this repository and set the project Root Directory to
`web`. Select “Other” as the framework and leave the build command empty.
After the backend has a public HTTPS URL, set that URL in
`web/config.js` as `window.STUDY_PLANNER_API_URL`. Add the Vercel URL to
`STUDY_PLANNER_ALLOWED_ORIGINS` in the backend environment.

Do not deploy the current SQLite backend as a Vercel Function: Functions are
request-based and cannot host the continuously running reminder worker. The
Docker deployment above is the reliable option. Render can host the API for
free for testing, but its free web services sleep and have no persistent local
disk; use a persistent database or paid disk for real reminders and data.
