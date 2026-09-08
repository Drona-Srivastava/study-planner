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

  function open(payload) {
    root.opened = true
    refresh()
    Qt.callLater(function() { focusItem.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    if (root.shell)
      root.shell.hide((root.manifest && root.manifest.id) || "study-planner")
  }

  function refresh() {
    root.error = ""
    agendaProc.running = false
    agendaProc.running = true
    taskProc.running = false
    taskProc.running = true
  }

  function run(args) {
    mutation.command = ["python3", root.script].concat(args)
    mutation.running = true
  }

  function addTask() {
    var title = newTask.text.trim()
    if (title === "")
      return

    var args = ["add", title, "--column", "Backlog"]
    if (newTaskDate.text.trim() !== "")
      args = args.concat(["--due", newTaskDate.text.trim()])
    if (newTaskTime.text.trim() !== "")
      args = args.concat(["--due-time", newTaskTime.text.trim()])
    root.run(args)
    newTask.text = ""
    newTaskDate.text = ""
    newTaskTime.text = ""
  }

  Process {
    id: agendaProc
    command: ["python3", root.script, "agenda"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.agendaData = JSON.parse(text || "{}")
        } catch (e) {
          root.error = "Invalid agenda response"
        }
      }
    }
    onExited: function(code) {
      if (code !== 0)
        root.error = "Could not load timetable"
    }
  }

  Process {
    id: taskProc
    command: ["python3", root.script, "tasks"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          root.taskData = data.tasks || []
        } catch (e) {
          root.error = "Invalid task response"
        }
      }
    }
  }

  Process {
    id: mutation
    onExited: function(code) {
      if (code !== 0)
        root.error = "Task operation failed"
      refresh()
    }
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "study-planner"
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.42)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    Item {
      id: focusItem
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(1120, parent.width - 32)
        height: Math.min(720, parent.height - 64)
        radius: Style.cornerRadius
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: focusItem.forceActiveFocus() }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(18)
          spacing: Style.space(12)

          RowLayout {
            Layout.fillWidth: true
            height: Style.space(36)
            Text {
              text: "STUDY PLANNER"
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.agendaData.date || ""
              color: Color.menu.text
              opacity: 0.65
              font.family: Style.font.family
            }
            Text {
              text: "×"
              color: Color.menu.text
              font.pixelSize: 24
              MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Repeater {
              model: ["Agenda", "Kanban"]
              delegate: Rectangle {
                required property string modelData
                Layout.fillWidth: true
                height: 34
                radius: 8
                color: root.tab === modelData
                  ? Color.accent
                  : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.08)
                Text {
                  anchors.centerIn: parent
                  text: parent.modelData
                  color: root.tab === parent.modelData
                    ? Color.menu.background
                    : Color.menu.text
                  font.family: Style.font.family
                }
                MouseArea { anchors.fill: parent; onClicked: root.tab = parent.modelData }
              }
            }
          }

          Text {
            visible: root.error !== ""
            text: root.error
            color: Color.urgent
            Layout.fillWidth: true
            elide: Text.ElideRight
          }

          StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.tab === "Agenda" ? 0 : 1

            Flickable {
              contentWidth: width
              contentHeight: agendaColumn.implicitHeight
              clip: true

              ColumnLayout {
                id: agendaColumn
                width: parent.width
                spacing: 10

                Rectangle {
                  Layout.fillWidth: true
                  height: 104
                  radius: 10
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                  border.color: Color.accent

                  Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 5
                    Text {
                      text: root.agendaData.current
                        ? "CURRENT · " + root.agendaData.current.category
                        : "NO ACTIVE BLOCK"
                      color: Color.accent
                      font.family: Style.font.family
                      font.bold: true
                    }
                    Text {
                      text: root.agendaData.current
                        ? root.agendaData.current.title
                        : "No actionable timetable block is active"
                      color: Color.menu.text
                      font.family: Style.font.family
                      elide: Text.ElideRight
                      width: parent.width
                    }
                    Row {
                      spacing: 8
                      Text {
                        text: root.agendaData.current
                          ? root.agendaData.current.start_time + "–" + root.agendaData.current.end_time
                          : ""
                        color: Color.menu.text
                        font.family: Style.font.family
                      }
                      CheckBox {
                        visible: !!root.agendaData.current
                        text: "done"
                        onClicked: if (checked)
                          root.run(["complete-block", String(root.agendaData.current.id)])
                      }
                    }
                  }
                }

                Text {
                  text: root.agendaData.next
                    ? "NEXT · " + root.agendaData.next.start_time + " · " + root.agendaData.next.title
                    : "No more actionable blocks today"
                  color: Color.menu.text
                  font.family: Style.font.family
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
                Text {
                  text: "TODAY"
                  color: Color.menu.text
                  opacity: 0.6
                  font.family: Style.font.family
                  font.bold: true
                }
                Repeater {
                  model: root.agendaData.items || []
                  delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 48
                    radius: 8
                    color: modelData.status === "completed"
                      ? Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.05)
                      : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.09)
                    RowLayout {
                      anchors.fill: parent
                      anchors.margins: 10
                      Text {
                        text: modelData.start_time + "  " + modelData.end_time
                        color: Color.menu.text
                        font.family: Style.font.family
                        Layout.preferredWidth: 118
                      }
                      Text {
                        text: modelData.title
                        color: Color.menu.text
                        font.family: Style.font.family
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                      }
                      Text {
                        text: modelData.status
                        color: modelData.status === "completed" ? Color.accent : Color.menu.text
                        opacity: 0.7
                        font.family: Style.font.family
                      }
                    }
                  }
                }
              }
            }

            Item {
              id: boardView
              property int boardGap: 10

              ColumnLayout {
                anchors.fill: parent
                spacing: 8

                RowLayout {
                  Layout.fillWidth: true
                  TextField {
                    id: newTask
                    placeholderText: "Task title — @14-08-26 or @@13:00"
                    Layout.fillWidth: true
                    onAccepted: root.addTask()
                  }
                  TextField {
                    id: newTaskDate
                    placeholderText: "@14-08-26"
                    Layout.preferredWidth: 125
                    ToolTip.visible: hovered
                    ToolTip.text: "Due date: @14-08-26"
                  }
                  TextField {
                    id: newTaskTime
                    placeholderText: "@@13:00"
                    Layout.preferredWidth: 100
                    ToolTip.visible: hovered
                    ToolTip.text: "Due time: @@13:00"
                  }
                  Button { text: "Add"; onClicked: root.addTask() }
                }

                Text {
                  text: "Drag cards between columns · use @ for a due date and @@ for a due time"
                  color: Color.menu.text
                  opacity: 0.6
                  font.family: Style.font.family
                  Layout.fillWidth: true
                }

                RowLayout {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  spacing: boardView.boardGap

                  Repeater {
                    model: ["Backlog", "In Progress", "Completed"]
                    delegate: DropArea {
                      id: dropColumn
                      required property string modelData
                      property string columnName: modelData
                      property var visibleTasks: root.taskData.filter(function(task) {
                        return task.column_name === dropColumn.columnName
                      })
                      keys: ["study-task"]
                      Layout.fillWidth: true
                      Layout.fillHeight: true

                      Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: dropColumn.containsDrag
                          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
                          : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.06)
                        border.color: dropColumn.containsDrag ? Color.accent : Color.menu.border
                        border.width: dropColumn.containsDrag ? 2 : 1
                      }

                      ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                          Layout.fillWidth: true
                          Text {
                            text: dropColumn.columnName
                            color: Color.menu.text
                            font.family: Style.font.family
                            font.bold: true
                          }
                          Item { Layout.fillWidth: true }
                          Text {
                            text: dropColumn.visibleTasks.length
                            color: Color.accent
                            font.family: Style.font.family
                          }
                        }

                        Flickable {
                          Layout.fillWidth: true
                          Layout.fillHeight: true
                          contentWidth: width
                          contentHeight: cardColumn.implicitHeight
                          clip: true

                          ColumnLayout {
                            id: cardColumn
                            width: parent.width
                            spacing: 7

                            Repeater {
                              model: dropColumn.visibleTasks
                              delegate: Rectangle {
                                id: taskCard
                                required property var modelData
                                property int taskId: modelData.id
                                Layout.fillWidth: true
                                height: taskDetails.implicitHeight + 20
                                radius: 8
                                color: dragHandler.active
                                  ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.24)
                                  : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10)
                                border.color: dragHandler.active ? Color.accent : "transparent"
                                opacity: dragHandler.active ? 0.78 : 1

                                Drag.active: dragHandler.active
                                Drag.keys: ["study-task"]
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                DragHandler { id: dragHandler; target: null }

                                ColumnLayout {
                                  id: taskDetails
                                  anchors.fill: parent
                                  anchors.margins: 10
                                  spacing: 5
                                  RowLayout {
                                    Layout.fillWidth: true
                                    CheckBox {
                                      checked: taskCard.modelData.column_name === "Completed"
                                      onClicked: root.run(["move", String(taskCard.taskId), checked ? "Completed" : "In Progress"])
                                    }
                                    Text {
                                      text: taskCard.modelData.title
                                      color: Color.menu.text
                                      font.family: Style.font.family
                                      wrapMode: Text.WordWrap
                                      Layout.fillWidth: true
                                    }
                                  }
                                  Text {
                                    visible: taskCard.modelData.due_date !== "" || taskCard.modelData.due_time !== ""
                                    text: (taskCard.modelData.due_date !== "" ? "@" + taskCard.modelData.due_date : "")
                                      + (taskCard.modelData.due_time !== "" ? "  @@" + taskCard.modelData.due_time : "")
                                    color: Color.accent
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                  }
                                  RowLayout {
                                    Layout.fillWidth: true
                                    Button {
                                      visible: taskCard.modelData.column_name === "Backlog"
                                      text: "Start"
                                      onClicked: root.run(["move", String(taskCard.taskId), "In Progress"])
                                    }
                                    Button {
                                      visible: taskCard.modelData.column_name !== "Completed"
                                      text: "Complete"
                                      onClicked: root.run(["move", String(taskCard.taskId), "Completed"])
                                    }
                                    Button {
                                      visible: taskCard.modelData.column_name === "Completed"
                                      text: "Reopen"
                                      onClicked: root.run(["move", String(taskCard.taskId), "In Progress"])
                                    }
                                    Item { Layout.fillWidth: true }
                                    Button { text: "×"; onClicked: root.run(["delete", String(taskCard.taskId)]) }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }

                      onDropped: function(drop) {
                        if (drop.source && drop.source.taskId !== undefined)
                          root.run(["move", String(drop.source.taskId), dropColumn.columnName])
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
