import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "study-planner"
  readonly property string script: Qt.resolvedUrl("planner.py").toString().replace(/^file:\/\//, "")
  property string label: "Study"
  property string nextTime: ""

  function refresh() { if (!proc.running) proc.running = true }
  function openPanel() { if (root.bar) root.bar.run("omarchy-shell shell toggle study-planner") }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    command: ["python3", root.script, "agenda"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          var item = data.current || data.next
          root.label = item ? String(item.category || "Study") : "Study"
          root.nextTime = item ? String(item.start_time || "") : ""
        } catch (e) {}
      }
    }
  }

  Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf14d"
    tooltipText: root.nextTime ? root.label + " · " + root.nextTime : "Study Planner"
    onPressed: function(mouseButton) { if (mouseButton === Qt.LeftButton) root.openPanel() }
  }
}
