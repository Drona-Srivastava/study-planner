import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property var shell: null
  readonly property string script: Qt.resolvedUrl("planner.py").toString().replace(/^file:\/\//, "")

  function check() { if (!proc.running) proc.running = true }

  Process {
    id: proc
    command: ["python3", root.script, "reminders"]
    stdout: StdioCollector {
      onStreamFinished: {
        // The backend calculates and sends deduplicated notifications.
      }
    }
  }

  Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.check() }
}
