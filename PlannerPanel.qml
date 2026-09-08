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
  property int relativeTick: 0
  property var datePickerMonth: new Date()
  property int datePickerDay: new Date().getDate()
  readonly property string uiFont: Style.font.menuFamily
  readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
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

    root.run(["add", title, "--column", "Backlog"])
    newTask.text = ""
  }

  function displayDate(value) {
    var match = String(value || "").match(/^(\d{4})-(\d{2})-(\d{2})$/)
    return match ? match[3] + "/" + match[2] + "/" + match[1].slice(2) : String(value || "")
  }

  function showTokenPicker() {
    var value = newTask.text
    if (value.endsWith("@@")) {
      datePopup.close()
      timePopup.open()
    } else if (value.endsWith("@")) {
      timePopup.close()
      datePopup.open()
    }
  }

  function scheduleTokenPicker() {
    if (newTask.text.endsWith("@"))
      tokenPickerTimer.restart()
    else
      tokenPickerTimer.stop()
  }

  function daysInMonth(date) {
    return new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()
  }

  function firstDayMondayIndex(date) {
    return (new Date(date.getFullYear(), date.getMonth(), 1).getDay() + 6) % 7
  }

  function shiftPickerMonth(delta) {
    root.datePickerMonth = new Date(root.datePickerMonth.getFullYear(), root.datePickerMonth.getMonth() + delta, 1)
    root.datePickerDay = Math.min(root.datePickerDay, root.daysInMonth(root.datePickerMonth))
  }

  function movePickerDay(delta) {
    var date = new Date(root.datePickerMonth.getFullYear(), root.datePickerMonth.getMonth(), root.datePickerDay)
    date.setDate(date.getDate() + delta)
    root.datePickerMonth = new Date(date.getFullYear(), date.getMonth(), 1)
    root.datePickerDay = date.getDate()
  }

  function dueRelative(dateValue, timeValue) {
    void(relativeTick)
    if (!dateValue)
      return timeValue ? "Due at " + timeValue : ""
    var parts = String(dateValue).split("-")
    if (parts.length !== 3)
      return ""
    var timeParts = String(timeValue || "23:59").split(":")
    var due = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), Number(timeParts[0] || 23), Number(timeParts[1] || 59))
    var difference = due.getTime() - new Date().getTime()
    var future = difference >= 0
    var totalMinutes = Math.max(1, Math.ceil(Math.abs(difference) / 60000))
    var days = Math.floor(totalMinutes / 1440)
    var hours = Math.floor((totalMinutes % 1440) / 60)
    var minutes = totalMinutes % 60
    var text = ""
    if (days > 0) text += days + "d "
    if (hours > 0 || days > 0) text += hours + "h "
    if (days === 0 && hours === 0) text += minutes + "m"
    return (future ? "Due in " : "Overdue by ") + text.trim()
  }

  function blockCanUndo(updatedAt) {
    if (!updatedAt)
      return false
    var completedAt = new Date(updatedAt).getTime()
    return isFinite(completedAt) && new Date().getTime() - completedAt <= 180000
  }

  function insertDate(date) {
    var day = String(date.getDate()).padStart(2, "0")
    var month = String(date.getMonth() + 1).padStart(2, "0")
    var year = String(date.getFullYear()).slice(-2)
    newTask.text = newTask.text.slice(0, -1) + "@" + day + "/" + month + "/" + year
    datePopup.close()
    newTask.forceActiveFocus()
  }

  function insertTime() {
    var hour = String(hourPicker.value).padStart(2, "0")
    var minute = String(minutePicker.value).padStart(2, "0")
    newTask.text = newTask.text.slice(0, -2) + "@@" + hour + ":" + minute
    timePopup.close()
    newTask.forceActiveFocus()
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

  Timer {
    id: tokenPickerTimer
    interval: 280
    repeat: false
    onTriggered: root.showTokenPicker()
  }

  Timer {
    interval: 60000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.relativeTick++
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
        width: Math.min(1060, parent.width - 64)
        height: Math.min(640, parent.height - 96)
        radius: 16
        color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.97)
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.42)
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: focusItem.forceActiveFocus() }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(20)
          spacing: Style.space(14)

          RowLayout {
            Layout.fillWidth: true
            height: Style.space(40)
            Text {
              text: "STUDY PLANNER"
              color: Color.menu.text
              font.family: root.uiFont
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 1.4
            }
            Item { Layout.fillWidth: true }
            Rectangle {
              implicitWidth: 82
              implicitHeight: 30
              radius: 8
              color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.08)
              border.color: Color.menu.border
              Text {
                anchors.centerIn: parent
                text: root.displayDate(root.agendaData.date)
                color: Color.menu.text
                opacity: 0.82
                font.family: root.uiFont
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
            Rectangle {
              implicitWidth: 32
              implicitHeight: 30
              radius: 8
              color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.08)
              Text {
                anchors.centerIn: parent
                text: "×"
                color: Color.menu.text
                font.family: root.uiFont
                font.pixelSize: 23
                font.bold: true
              }
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
                height: 40
                radius: 10
                color: root.tab === modelData
                  ? Color.accent
                  : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.08)
                Text {
                  anchors.centerIn: parent
                  text: parent.modelData.toUpperCase()
                  color: root.tab === parent.modelData
                    ? Color.menu.background
                    : Color.menu.text
                  font.family: root.uiFont
                  font.pixelSize: Style.font.body
                  font.bold: true
                  font.letterSpacing: 0.8
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
                  height: 116
                  radius: 10
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                  border.color: Color.accent
                  border.width: 1

                  Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 5
                    Text {
                      text: root.agendaData.current
                        ? "CURRENT · " + root.agendaData.current.category
                        : "NO ACTIVE BLOCK"
                      color: Color.accent
                      font.family: root.uiFont
                      font.pixelSize: Style.font.bodySmall + 1
                      font.letterSpacing: 1.1
                      font.bold: true
                    }
                    Text {
                      text: root.agendaData.current
                        ? root.agendaData.current.title
                        : "No actionable timetable block is active"
                      color: Color.menu.text
                      font.family: root.uiFont
                      font.pixelSize: Style.font.subtitle + 1
                      font.bold: true
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
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall + 1
                      }
                      CheckBox {
                        visible: !!root.agendaData.current
                        text: "done"
                        onClicked: root.run([checked ? "complete-block" : "uncomplete-block", String(root.agendaData.current.id)])
                      }
                    }
                  }
                }

                Text {
                  text: "UP NEXT"
                  color: Color.accent
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall + 1
                  font.letterSpacing: 1.1
                  font.bold: true
                  Layout.fillWidth: true
                }
                Rectangle {
                  Layout.fillWidth: true
                  height: root.agendaData.next ? 62 : 46
                  radius: 8
                  color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.08)
                  border.color: root.agendaData.next
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.42)
                    : Color.menu.border
                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    Text {
                      text: root.agendaData.next
                        ? root.agendaData.next.start_time + "–" + root.agendaData.next.end_time
                        : "—"
                      color: Color.menu.text
                      font.family: root.uiFont
                      font.pixelSize: Style.font.bodySmall + 1
                      font.bold: true
                      Layout.preferredWidth: 112
                    }
                    Text {
                      text: root.agendaData.next
                        ? root.agendaData.next.title
                        : "No more scheduled blocks today"
                      color: Color.menu.text
                      opacity: root.agendaData.next ? 1 : 0.65
                      font.family: root.uiFont
                      font.pixelSize: Style.font.subtitle + 1
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                  }
                }
                Text {
                  text: "TODAY'S SCHEDULE"
                  color: Color.menu.text
                  opacity: 0.72
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall + 1
                  font.letterSpacing: 1.1
                  font.bold: true
                }
                Repeater {
                  model: root.agendaData.items || []
                  delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 56
                    radius: 8
                    color: modelData.status === "completed"
                      ? Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.05)
                      : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.09)
                    RowLayout {
                      anchors.fill: parent
                      anchors.margins: 10
                      CheckBox {
                        visible: !modelData.event
                        checked: modelData.status === "completed"
                        enabled: modelData.status !== "completed" || root.blockCanUndo(modelData.updated_at)
                        onClicked: root.run([checked ? "complete-block" : "uncomplete-block", String(modelData.id)])
                      }
                      Text {
                        text: modelData.start_time + "–" + modelData.end_time
                        color: Color.menu.text
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall + 1
                        font.bold: true
                        Layout.preferredWidth: 120
                      }
                      Text {
                        text: modelData.title
                        color: Color.menu.text
                        font.family: root.uiFont
                        font.pixelSize: Style.font.subtitle + 1
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                      }
                      Text {
                        text: modelData.category === "CLASS" ? "CLASS" : modelData.status
                        color: modelData.status === "completed" ? Color.accent : Color.menu.text
                        opacity: 0.7
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall + 1
                        font.bold: true
                        Layout.preferredWidth: 58
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
                    placeholderText: "Task title"
                    font.family: root.uiFont
                    font.pixelSize: Style.font.body + 1
                    Layout.fillWidth: true
                    background: Rectangle {
                      radius: 9
                      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.07)
                      border.color: newTask.activeFocus ? Color.accent : Color.menu.border
                      border.width: newTask.activeFocus ? 2 : 1
                    }
                    onAccepted: root.addTask()
                    onTextChanged: root.scheduleTokenPicker()
                  }
                  Rectangle {
                    implicitWidth: 72
                    implicitHeight: 38
                    radius: 9
                    color: Color.accent
                    Text {
                      anchors.centerIn: parent
                      text: "ADD"
                      color: Color.menu.background
                      font.family: root.uiFont
                      font.pixelSize: Style.font.bodySmall + 1
                      font.bold: true
                      font.letterSpacing: 0.8
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.addTask() }
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  spacing: boardView.boardGap

                  Repeater {
                    model: ["Backlog", "In Progress", "Completed"]
                    delegate: Rectangle {
                      id: columnCard
                      required property string modelData
                      property string columnName: modelData
                      property var visibleTasks: root.taskData.filter(function(task) {
                        return task.column_name === columnCard.columnName
                      })
                      Layout.fillWidth: true
                      Layout.fillHeight: true
                      radius: 10
                      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.06)
                      border.color: Color.menu.border
                      border.width: 1

                      ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                          Layout.fillWidth: true
                          Text {
                            text: columnCard.columnName.toUpperCase()
                            color: Color.menu.text
                            font.family: root.uiFont
                            font.pixelSize: Style.font.bodySmall + 1
                            font.letterSpacing: 0.9
                            font.bold: true
                          }
                          Item { Layout.fillWidth: true }
                          Text {
                            text: columnCard.visibleTasks.length
                            color: Color.accent
                            font.family: root.uiFont
                            font.pixelSize: Style.font.bodySmall + 1
                            font.bold: true
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
                              model: columnCard.visibleTasks
                              delegate: Rectangle {
                                id: taskCard
                                required property var modelData
                                property int taskId: modelData.id
                                Layout.fillWidth: true
                                height: taskDetails.implicitHeight + 20
                                radius: 8
                                color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.11)
                                border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
                                border.width: 1

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
                                      font.family: root.uiFont
                                      font.pixelSize: Style.font.subtitle + 1
                                      font.bold: true
                                      wrapMode: Text.WordWrap
                                      Layout.fillWidth: true
                                    }
                                  }
                                  Text {
                                    visible: taskCard.modelData.due_date !== "" || taskCard.modelData.due_time !== ""
                                    text: root.dueRelative(taskCard.modelData.due_date, taskCard.modelData.due_time)
                                    color: Color.accent
                                    font.family: root.uiFont
                                    font.bold: true
                                    font.pixelSize: Style.font.bodySmall + 1
                                    opacity: 1
                                  }
                                  RowLayout {
                                    Layout.fillWidth: true
                                    Button {
                                      visible: taskCard.modelData.column_name === "Backlog"
                                      text: "START"
                                      onClicked: root.run(["move", String(taskCard.taskId), "In Progress"])
                                    }
                                    Button {
                                      visible: taskCard.modelData.column_name !== "Completed"
                                      text: "COMPLETE"
                                      onClicked: root.run(["move", String(taskCard.taskId), "Completed"])
                                    }
                                    Button {
                                      visible: taskCard.modelData.column_name === "Completed"
                                      text: "REOPEN"
                                      onClicked: root.run(["move", String(taskCard.taskId), "In Progress"])
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                      implicitWidth: 38
                                      implicitHeight: 32
                                      radius: 8
                                      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10)
                                      border.color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.16)
                                      Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        color: Color.menu.text
                                        font.family: root.uiFont
                                        font.pixelSize: 24
                                        font.bold: true
                                      }
                                      MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.run(["delete", String(taskCard.taskId)])
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
              }
            }
          }
        }
      }
    }

    Popup {
      id: datePopup
      width: 360
      height: 360
      modal: true
      focus: true
      x: Math.round((parent.width - width) / 2)
      y: Math.round((parent.height - height) / 2)
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      onOpened: {
        var today = new Date()
        root.datePickerMonth = new Date(today.getFullYear(), today.getMonth(), 1)
        root.datePickerDay = today.getDate()
        dateKeyCatcher.forceActiveFocus()
      }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Left) root.movePickerDay(-1)
        else if (event.key === Qt.Key_Right) root.movePickerDay(1)
        else if (event.key === Qt.Key_Up) root.movePickerDay(-7)
        else if (event.key === Qt.Key_Down) root.movePickerDay(7)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.insertDate(new Date(root.datePickerMonth.getFullYear(), root.datePickerMonth.getMonth(), root.datePickerDay))
        else return
        event.accepted = true
      }

      background: Rectangle {
        radius: 12
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: 1
      }

      Item {
        id: dateKeyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Left) root.movePickerDay(-1)
          else if (event.key === Qt.Key_Right) root.movePickerDay(1)
          else if (event.key === Qt.Key_Up) root.movePickerDay(-7)
          else if (event.key === Qt.Key_Down) root.movePickerDay(7)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.insertDate(new Date(root.datePickerMonth.getFullYear(), root.datePickerMonth.getMonth(), root.datePickerDay))
          else return
          event.accepted = true
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        Text {
          text: "SELECT DUE DATE · DD/MM/YY"
          color: Color.accent
          font.family: Style.font.family
          font.bold: true
        }
        RowLayout {
          Layout.fillWidth: true
          Button { text: "‹"; onClicked: root.shiftPickerMonth(-1) }
          Text {
            text: root.monthNames[root.datePickerMonth.getMonth()] + " " + root.datePickerMonth.getFullYear()
            color: Color.menu.text
            font.family: Style.font.family
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
          }
          Button { text: "›"; onClicked: root.shiftPickerMonth(1) }
        }
        GridLayout {
          columns: 7
          Layout.fillWidth: true
          Layout.fillHeight: true
          Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            delegate: Text {
              required property string modelData
              text: modelData
              color: Color.menu.text
              opacity: 0.6
              font.family: Style.font.family
              horizontalAlignment: Text.AlignHCenter
              Layout.fillWidth: true
            }
          }
          Repeater {
            model: 42
            delegate: Rectangle {
              required property int index
              readonly property int dayNumber: index - root.firstDayMondayIndex(root.datePickerMonth) + 1
              enabled: dayNumber > 0 && dayNumber <= root.daysInMonth(root.datePickerMonth)
              radius: 6
              color: enabled && dayNumber === root.datePickerDay
                ? Color.accent
                : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.08)
              border.color: enabled && dayNumber === root.datePickerDay ? Color.accent : "transparent"
              Layout.fillWidth: true
              Layout.fillHeight: true
              Text {
                anchors.centerIn: parent
                text: parent.enabled ? String(parent.dayNumber) : ""
                color: parent.dayNumber === root.datePickerDay ? Color.menu.background : Color.menu.text
                font.family: Style.font.family
              }
              MouseArea {
                anchors.fill: parent
                enabled: parent.enabled
                onClicked: {
                  root.datePickerDay = parent.dayNumber
                  root.insertDate(new Date(root.datePickerMonth.getFullYear(), root.datePickerMonth.getMonth(), parent.dayNumber))
                }
              }
            }
          }
        }
        Button { text: "Cancel"; Layout.alignment: Qt.AlignRight; onClicked: datePopup.close() }
      }
    }

    Popup {
      id: timePopup
      width: 300
      height: 210
      modal: true
      focus: true
      x: Math.round((parent.width - width) / 2)
      y: Math.round((parent.height - height) / 2)
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up) hourPicker.value = Math.min(hourPicker.to, hourPicker.value + 1)
        else if (event.key === Qt.Key_Down) hourPicker.value = Math.max(hourPicker.from, hourPicker.value - 1)
        else if (event.key === Qt.Key_Right) minutePicker.value = Math.min(minutePicker.to, minutePicker.value + 1)
        else if (event.key === Qt.Key_Left) minutePicker.value = Math.max(minutePicker.from, minutePicker.value - 1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.insertTime()
        else return
        event.accepted = true
      }
      onOpened: {
        var current = new Date()
        hourPicker.value = current.getHours()
        minutePicker.value = current.getMinutes()
        timeKeyCatcher.forceActiveFocus()
      }

      background: Rectangle {
        radius: 12
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: 1
      }

      Item {
        id: timeKeyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Up) hourPicker.value = Math.min(hourPicker.to, hourPicker.value + 1)
          else if (event.key === Qt.Key_Down) hourPicker.value = Math.max(hourPicker.from, hourPicker.value - 1)
          else if (event.key === Qt.Key_Right) minutePicker.value = Math.min(minutePicker.to, minutePicker.value + 1)
          else if (event.key === Qt.Key_Left) minutePicker.value = Math.max(minutePicker.from, minutePicker.value - 1)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.insertTime()
          else return
          event.accepted = true
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12
        Text {
          text: "SELECT DUE TIME · 24 HOUR"
          color: Color.accent
          font.family: Style.font.family
          font.bold: true
        }
        RowLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: 10
          SpinBox {
            id: hourPicker
            from: 0; to: 23; value: 0; editable: false; stepSize: 1
            implicitWidth: 88; implicitHeight: 56
            contentItem: Text {
              text: String(hourPicker.value).padStart(2, "0")
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: 26
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { radius: 8; color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10); border.color: Color.menu.border }
            up.indicator: Rectangle {
              x: 64; width: 24; height: 28
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
              Text { anchors.centerIn: parent; text: "▲"; color: Color.accent; font.pixelSize: 11 }
              MouseArea { anchors.fill: parent; onClicked: hourPicker.value = Math.min(hourPicker.to, hourPicker.value + 1) }
            }
            down.indicator: Rectangle {
              x: 64; y: 28; width: 24; height: 28
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
              Text { anchors.centerIn: parent; text: "▼"; color: Color.accent; font.pixelSize: 11 }
              MouseArea { anchors.fill: parent; onClicked: hourPicker.value = Math.max(hourPicker.from, hourPicker.value - 1) }
            }
          }
          Text { text: ":"; color: Color.menu.text; font.pixelSize: 26; font.bold: true }
          SpinBox {
            id: minutePicker
            from: 0; to: 59; value: 0; editable: false; stepSize: 1
            implicitWidth: 88; implicitHeight: 56
            contentItem: Text {
              text: String(minutePicker.value).padStart(2, "0")
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: 26
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { radius: 8; color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10); border.color: Color.menu.border }
            up.indicator: Rectangle {
              x: 64; width: 24; height: 28
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
              Text { anchors.centerIn: parent; text: "▲"; color: Color.accent; font.pixelSize: 11 }
              MouseArea { anchors.fill: parent; onClicked: minutePicker.value = Math.min(minutePicker.to, minutePicker.value + 1) }
            }
            down.indicator: Rectangle {
              x: 64; y: 28; width: 24; height: 28
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
              Text { anchors.centerIn: parent; text: "▼"; color: Color.accent; font.pixelSize: 11 }
              MouseArea { anchors.fill: parent; onClicked: minutePicker.value = Math.max(minutePicker.from, minutePicker.value - 1) }
            }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          Item { Layout.fillWidth: true }
          Button { text: "Cancel"; onClicked: timePopup.close() }
          Button { text: "Use time"; onClicked: root.insertTime() }
        }
      }
    }
  }
}
