import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string tab: "Agenda"
  property var agendaData: ({items: [], current: null, next: null})
  property var taskData: []
  property string error: ""
  readonly property string script: Qt.resolvedUrl("planner.py").toString().replace(/^file:\/\//, "")

  function open(payload) { root.opened = true; refresh(); Qt.callLater(function() { focusItem.forceActiveFocus() }) }
  function close() { root.opened = false }
  function dismiss() { if (root.shell) root.shell.hide((root.manifest && root.manifest.id) || "study-planner") }
  function refresh() { agendaProc.running = false; agendaProc.running = true; taskProc.running = false; taskProc.running = true }
  function run(args) { mutation.command = ["python3", root.script].concat(args); mutation.running = true }

  Process {
    id: agendaProc; command: ["python3", root.script, "agenda"]
    stdout: StdioCollector { onStreamFinished: { try { var d = JSON.parse(text || "{}"); root.agendaData = d } catch(e) { root.error = "Invalid agenda response" } } }
    onExited: function(code) { if (code !== 0) root.error = "Could not load timetable" }
  }
  Process {
    id: taskProc; command: ["python3", root.script, "tasks"]
    stdout: StdioCollector { onStreamFinished: { try { var d = JSON.parse(text || "{}"); root.taskData = d.tasks || [] } catch(e) { root.error = "Invalid task response" } } }
  }
  Process { id: mutation; onExited: function(code) { if (code !== 0) root.error = "Task operation failed"; refresh() } }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "study-planner"
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle { anchors.fill: parent; color: Qt.rgba(0,0,0,0.42); MouseArea { anchors.fill: parent; onClicked: root.dismiss() } }
    Item {
      id: focusItem; anchors.fill: parent; focus: true
      Keys.onEscapePressed: root.dismiss()
      Rectangle {
        id: card; anchors.centerIn: parent; width: Math.min(980, parent.width - 32); height: Math.min(680, parent.height - 64)
        radius: Style.cornerRadius; color: Color.menu.background; border.color: Color.menu.border; border.width: 1
        MouseArea { anchors.fill: parent; onClicked: focusItem.forceActiveFocus() }
        ColumnLayout {
          anchors.fill: parent; anchors.margins: Style.space(18); spacing: Style.space(12)
          RowLayout { Layout.fillWidth: true; height: Style.space(36)
            Text { text: "STUDY PLANNER"; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
            Item { Layout.fillWidth: true }
            Text { text: root.agendaData.date || ""; color: Color.menu.text; opacity: 0.65; font.family: Style.font.family }
            Text { text: "×"; color: Color.menu.text; font.pixelSize: 24; MouseArea { anchors.fill: parent; onClicked: root.dismiss() } }
          }
          RowLayout { Layout.fillWidth: true
            Repeater { model: ["Agenda", "Kanban"]
              delegate: Rectangle { required property string modelData; Layout.fillWidth: true; height: 34; radius: 8; color: root.tab === modelData ? Color.accent : Qt.rgba(Color.menu.text.r,Color.menu.text.g,Color.menu.text.b,0.08)
                Text { anchors.centerIn: parent; text: parent.modelData; color: root.tab === parent.modelData ? Color.menu.background : Color.menu.text; font.family: Style.font.family }
                MouseArea { anchors.fill: parent; onClicked: root.tab = parent.modelData }
              }
            }
          }
          Text { visible: root.error !== ""; text: root.error; color: Color.urgent; Layout.fillWidth: true; elide: Text.ElideRight }
          StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: root.tab === "Agenda" ? 0 : 1
            Flickable { contentWidth: width; contentHeight: agendaColumn.implicitHeight; clip: true
              ColumnLayout { id: agendaColumn; width: parent.width; spacing: 10
                Rectangle { Layout.fillWidth: true; height: 104; radius: 10; color: Qt.rgba(Color.accent.r,Color.accent.g,Color.accent.b,0.14); border.color: Color.accent
                  Column { anchors.fill: parent; anchors.margins: 14; spacing: 5
                    Text { text: root.agendaData.current ? "CURRENT · " + root.agendaData.current.category : "NO ACTIVE BLOCK"; color: Color.accent; font.family: Style.font.family; font.bold: true }
                    Text { text: root.agendaData.current ? root.agendaData.current.title : "No actionable timetable block is active"; color: Color.menu.text; font.family: Style.font.family; elide: Text.ElideRight; width: parent.width }
                    Row { spacing: 8; Text { text: root.agendaData.current ? root.agendaData.current.start_time + "–" + root.agendaData.current.end_time : ""; color: Color.menu.text; font.family: Style.font.family }
                      CheckBox { visible: !!root.agendaData.current; text: "done"; onClicked: if (checked) root.run(["complete-block", String(root.agendaData.current.id)]) }
                    }
                  }
                }
                Text { text: root.agendaData.next ? "NEXT · " + root.agendaData.next.start_time + " · " + root.agendaData.next.title : "No more actionable blocks today"; color: Color.menu.text; font.family: Style.font.family; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Text { text: "TODAY"; color: Color.menu.text; opacity: 0.6; font.family: Style.font.family; font.bold: true }
                Repeater { model: root.agendaData.items || []; delegate: Rectangle { required property var modelData; Layout.fillWidth: true; height: 48; radius: 8; color: modelData.status === "completed" ? Qt.rgba(Color.menu.text.r,Color.menu.text.g,Color.menu.text.b,0.05) : Qt.rgba(Color.menu.text.r,Color.menu.text.g,Color.menu.text.b,0.09)
                    RowLayout { anchors.fill: parent; anchors.margins: 10; Text { text: modelData.start_time + "  " + modelData.end_time; color: Color.menu.text; font.family: Style.font.family; Layout.preferredWidth: 118 } Text { text: modelData.title; color: Color.menu.text; font.family: Style.font.family; elide: Text.ElideRight; Layout.fillWidth: true } Text { text: modelData.status; color: modelData.status === "completed" ? Color.accent : Color.menu.text; opacity: 0.7; font.family: Style.font.family } }
                  } }
              }
            }
            Flickable { contentWidth: width; contentHeight: boardColumn.implicitHeight; clip: true
              ColumnLayout { id: boardColumn; width: parent.width; spacing: 10
                RowLayout { Layout.fillWidth: true; TextField { id: newTask; placeholderText: "Add a task"; Layout.fillWidth: true } Button { text: "Add"; onClicked: { if (newTask.text.trim() !== "") { root.run(["add", newTask.text.trim(), "--column", "Backlog"]); newTask.text = "" } } } }
                Repeater { model: ["Backlog", "To Do", "Completed"]; delegate: ColumnLayout { required property string modelData; Layout.fillWidth: true; spacing: 5; Text { text: modelData; color: Color.accent; font.family: Style.font.family; font.bold: true }
                    Repeater { model: root.taskData.filter(function(t) { return t.column_name === modelData }); delegate: Rectangle { required property var modelData; Layout.fillWidth: true; height: 42; radius: 8; color: Qt.rgba(Color.menu.text.r,Color.menu.text.g,Color.menu.text.b,0.09); RowLayout { anchors.fill: parent; anchors.margins: 8; Text { text: modelData.title; color: Color.menu.text; elide: Text.ElideRight; Layout.fillWidth: true; font.family: Style.font.family } Button { text: modelData.column_name === "Completed" ? "↶" : "✓"; onClicked: root.run(["move", String(modelData.id), modelData.column_name === "Completed" ? "To Do" : "Completed"]) } Button { text: "×"; onClicked: root.run(["delete", String(modelData.id)]) } } } }
                  } }
              }
            }
          }
        }
      }
    }
  }
}
