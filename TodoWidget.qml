import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    WlrLayershell.namespace: "caelestia-todo-widget"
    // Bottom layer: desktop view only (sits directly on wallpaper, behind normal windows)
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        right: true
    }
    
    margins {
        top: 56
        right: 28
    }

    implicitWidth: 360
    // Dynamic height: fits whichever active tab is shown, no wasted empty space
    implicitHeight: Math.min(640, mainCard.implicitHeight)

    color: "transparent"

    // Caelestia Theme Palette (Catppuccin Mocha Tonalspot)
    readonly property color colSurface: "#1e1d22"
    readonly property color colSurfaceLow: "#161519"
    readonly property color colSurfaceHigh: "#2a292e"
    readonly property color colSurfaceHighest: "#353438"
    readonly property color colText: "#e5e1e7"
    readonly property color colTextVariant: "#c8c5d1"
    readonly property color colOutline: "#47464f"
    readonly property color colOutlineVariant: "#333238"
    readonly property color colPrimary: "#c2c1ff"
    readonly property color colTextOnPrimary: "#2a2a60"
    readonly property color colTertiary: "#f5b2e0"
    readonly property color colSuccess: "#B5CCBA"
    readonly property color colError: "#ffb4ab"

    // Primary Tab: "tasks" | "agenda"
    property string currentMainTab: "tasks"

    // Tasks State
    property string activeCategory: "today" // "today" | "daily"
    property string activeFilter: "all"     // "all" | "active" | "done"
    property var todayList: []
    property var dailyList: []
    property string lastResetDate: ""

    // Agenda State
    property string agendaFilter: "today" // "today" | "upcoming" | "all"
    property var allEvents: []

    function getTodayString() {
        var d = new Date()
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, '0') + "-" + String(d.getDate()).padStart(2, '0')
    }

    // --- Process Handlers for Tasks ---
    Process {
        id: initFile
        command: ["bash", "-c", "mkdir -p " + Quickshell.env.HOME + "/.local/state && touch " + Quickshell.env.HOME + "/.local/state/todos.json"]
        running: true
        onExited: {
            readProc.running = true
            syncCalendarProc.running = true
        }
    }

    Process {
        id: readProc
        command: ["bash", "-c", "cat " + Quickshell.env.HOME + "/.local/state/todos.json | tr -d '\n'"]
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim().length > 0) {
                    try {
                        var parsed = JSON.parse(data)
                        var curDate = root.getTodayString()

                        if (Array.isArray(parsed)) {
                            root.todayList = parsed
                            root.dailyList = []
                            root.lastResetDate = curDate
                        } else {
                            root.todayList = Array.isArray(parsed.today) ? parsed.today : []
                            root.dailyList = Array.isArray(parsed.daily) ? parsed.daily : []
                            root.lastResetDate = parsed.lastResetDate || curDate

                            if (root.lastResetDate !== curDate) {
                                for (var i = 0; i < root.dailyList.length; i++) {
                                    root.dailyList[i].done = false
                                }
                                root.lastResetDate = curDate
                                root.saveTodos()
                            }
                        }
                        root.syncTaskModel()
                    } catch (e) {
                        root.syncTaskModel()
                    }
                } else {
                    root.syncTaskModel()
                }
            }
        }
    }

    Process {
        id: writeProc
        property string content: "{}"
        command: ["bash", "-c", "cat << 'EOF' > " + Quickshell.env.HOME + "/.local/state/todos.json\n" + content + "\nEOF"]
    }

    function saveTodos() {
        var payload = {
            "lastResetDate": lastResetDate || getTodayString(),
            "today": todayList,
            "daily": dailyList
        }
        writeProc.content = JSON.stringify(payload, null, 2)
        writeProc.running = true
    }

    function syncTaskModel() {
        taskModel.clear()
        var source = (activeCategory === "today") ? todayList : dailyList
        for (var i = 0; i < source.length; i++) {
            var item = source[i]
            var matches = true
            if (activeFilter === "active" && item.done) matches = false
            if (activeFilter === "done" && !item.done) matches = false

            if (matches) {
                taskModel.append({
                    "rawIndex": i,
                    "text": item.text,
                    "done": item.done
                })
            }
        }
    }

    function toggleTask(rawIndex) {
        var source = (activeCategory === "today") ? todayList : dailyList
        if (rawIndex >= 0 && rawIndex < source.length) {
            source[rawIndex].done = !source[rawIndex].done
            saveTodos()
            syncTaskModel()
        }
    }

    function deleteTask(rawIndex) {
        var source = (activeCategory === "today") ? todayList : dailyList
        if (rawIndex >= 0 && rawIndex < source.length) {
            source.splice(rawIndex, 1)
            saveTodos()
            syncTaskModel()
        }
    }

    function addTask(text) {
        if (!text || text.trim().length === 0) return
        var item = { "text": text.trim(), "done": false }
        if (activeCategory === "today") {
            todayList.push(item)
        } else {
            dailyList.push(item)
        }
        saveTodos()
        syncTaskModel()
    }

    function resetDailyHabits() {
        for (var i = 0; i < dailyList.length; i++) {
            dailyList[i].done = false
        }
        saveTodos()
        syncTaskModel()
    }

    function countPending(list) {
        var c = 0
        for (var i = 0; i < list.length; i++) {
            if (!list[i].done) c++
        }
        return c
    }

    // --- Process Handlers for Agenda & Google Calendar ---
    Process {
        id: syncCalendarProc
        command: ["python3", "/home/zius/Projects/playground/calendar_sync.py"]
        onExited: readEventsProc.running = true
    }

    Process {
        id: readEventsProc
        command: ["bash", "-c", "cat " + Quickshell.env.HOME + "/.local/state/calendar_events.json | tr -d '\n'"]
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim().length > 0) {
                    try {
                        root.allEvents = JSON.parse(data)
                        root.syncAgendaModel()
                    } catch (e) {
                        root.syncAgendaModel()
                    }
                } else {
                    root.syncAgendaModel()
                }
            }
        }
    }

    Process {
        id: addLocalEventProc
        property string eventTitle: ""
        property string eventTime: ""
        command: ["python3", "-c", "import json, os, datetime; f='" + Quickshell.env.HOME + "/.local/state/calendar_local.json'; data=json.load(open(f)) if os.path.exists(f) else []; data.append({'id': int(datetime.datetime.now().timestamp()), 'title': '" + eventTitle + "', 'date': datetime.datetime.now().strftime('%Y-%m-%d'), 'time': '" + eventTime + "'}); json.dump(data, open(f, 'w'), indent=2)"]
        onExited: syncCalendarProc.running = true
    }

    Process {
        id: deleteLocalEventProc
        property int eventId: 0
        command: ["python3", "-c", "import json, os; f='" + Quickshell.env.HOME + "/.local/state/calendar_local.json'; data=[x for x in json.load(open(f)) if x.get('id') != " + eventId + "] if os.path.exists(f) else []; json.dump(data, open(f, 'w'), indent=2)"]
        onExited: syncCalendarProc.running = true
    }

    function syncAgendaModel() {
        agendaModel.clear()
        for (var i = 0; i < allEvents.length; i++) {
            var ev = allEvents[i]
            var matches = true
            if (agendaFilter === "today" && !ev.isToday) matches = false
            if (agendaFilter === "upcoming" && ev.isToday) matches = false

            if (matches) {
                agendaModel.append({
                    "title": ev.title,
                    "dateDisplay": ev.dateDisplay || ev.date,
                    "time": ev.time || "All Day",
                    "location": ev.location || "",
                    "isToday": ev.isToday,
                    "source": ev.source,
                    "eventId": ev.id || 0
                })
            }
        }
    }

    function countEvents(filterKey) {
        var count = 0
        for (var i = 0; i < allEvents.length; i++) {
            if (filterKey === "today" && allEvents[i].isToday) count++
            else if (filterKey === "upcoming" && !allEvents[i].isToday) count++
            else if (filterKey === "all") count++
        }
        return count
    }

    ListModel { id: taskModel }
    ListModel { id: agendaModel }

    // Outer Shell Card
    Rectangle {
        id: mainCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: cardLayout.implicitHeight + 24

        radius: 20
        color: root.colSurface
        border.color: root.colOutlineVariant
        border.width: 1

        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // ==========================================
            // Master Navigation: Sliding Pill Switcher
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 12
                color: root.colSurfaceLow

                // Animated sliding background pill
                Rectangle {
                    x: root.currentMainTab === "tasks" ? 3 : parent.width / 2 + 1
                    y: 3
                    width: parent.width / 2 - 4
                    height: parent.height - 6
                    radius: 9
                    color: root.currentMainTab === "tasks" ? root.colPrimary : root.colTertiary

                    Behavior on x {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 180 }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Tasks Tab Pill
                    Rectangle { color: "transparent"
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "task_alt"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 16
                                color: root.currentMainTab === "tasks" ? root.colTextOnPrimary : root.colTextVariant
                            }
                            Text {
                                text: "Tasks"
                                font.pixelSize: 13
                                font.bold: true
                                color: root.currentMainTab === "tasks" ? root.colTextOnPrimary : root.colTextVariant
                            }
                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                color: root.currentMainTab === "tasks" ? root.colTextOnPrimary : root.colSurfaceHigh
                                Text {
                                    anchors.centerIn: parent
                                    text: String(root.countPending(root.todayList) + root.countPending(root.dailyList))
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.currentMainTab === "tasks" ? root.colPrimary : root.colTextVariant
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentMainTab = "tasks"
                        }
                    }

                    // Agenda / Calendar Tab Pill
                    Rectangle { color: "transparent"
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "calendar_month"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 16
                                color: root.currentMainTab === "agenda" ? "#2a1526" : root.colTextVariant
                            }
                            Text {
                                text: "Calendar"
                                font.pixelSize: 13
                                font.bold: true
                                color: root.currentMainTab === "agenda" ? "#2a1526" : root.colTextVariant
                            }
                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                color: root.currentMainTab === "agenda" ? "#2a1526" : root.colSurfaceHigh
                                Text {
                                    anchors.centerIn: parent
                                    text: String(root.countEvents("all"))
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.currentMainTab === "agenda" ? root.colTertiary : root.colTextVariant
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentMainTab = "agenda"
                                syncCalendarProc.running = true
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Sliding Views Container
            // ==========================================
            Item {
                id: slidingContainer
                Layout.fillWidth: true
                implicitHeight: (root.currentMainTab === "tasks" ? tasksView.implicitHeight : agendaView.implicitHeight)
                clip: true

                // ------------------------------------------
                // View 1: Tasks (Today / Daily)
                // ------------------------------------------
                ColumnLayout {
                    id: tasksView
                    width: slidingContainer.width
                    spacing: 10
                    opacity: root.currentMainTab === "tasks" ? 1 : 0
                    visible: opacity > 0
                    x: root.currentMainTab === "tasks" ? 0 : -slidingContainer.width

                    Behavior on x {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 180 }
                    }

                    // Category Switcher: Today vs Daily
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            implicitWidth: 80
                            implicitHeight: 32
                            Layout.fillWidth: true
                            radius: 9
                            color: root.activeCategory === "today" ? root.colPrimary : root.colSurfaceHigh
                            Behavior on color { ColorAnimation { duration: 140 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "Today"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: root.activeCategory === "today" ? root.colTextOnPrimary : root.colText
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeCategory = "today"
                                    root.syncTaskModel()
                                }
                            }
                        }

                        Rectangle {
                            implicitWidth: 80
                            implicitHeight: 32
                            Layout.fillWidth: true
                            radius: 9
                            color: root.activeCategory === "daily" ? root.colTertiary : root.colSurfaceHigh
                            Behavior on color { ColorAnimation { duration: 140 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "Daily"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: root.activeCategory === "daily" ? "#2a1526" : root.colText
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeCategory = "daily"
                                    root.syncTaskModel()
                                }
                            }
                        }

                        Rectangle {
                            visible: root.activeCategory === "daily" && root.dailyList.length > 0
                            width: 32
                            height: 32
                            radius: 9
                            color: root.colSurfaceHigh
                            Text {
                                anchors.centerIn: parent
                                text: "↻"
                                font.pixelSize: 15
                                font.bold: true
                                color: root.colTertiary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.resetDailyHabits()
                            }
                        }
                    }

                    // Filter Pills
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { "key": "all", "label": "All" },
                                { "key": "active", "label": "Active" },
                                { "key": "done", "label": "Done" }
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 24
                                radius: 7
                                color: root.activeFilter === modelData.key ? root.colSurfaceHighest : "transparent"
                                border.color: root.activeFilter === modelData.key ? root.colOutline : "transparent"
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: 11
                                    font.weight: root.activeFilter === modelData.key ? Font.Medium : Font.Normal
                                    color: root.activeFilter === modelData.key ? root.colText : root.colOutline
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.activeFilter = modelData.key
                                        root.syncTaskModel()
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.colOutlineVariant
                    }

                    // Task List View
                    ListView {
                        id: taskListView
                        Layout.fillWidth: true
                        implicitHeight: Math.min(320, contentHeight)
                        clip: true
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 350; easing.type: Easing.OutExpo }
                                NumberAnimation { property: "x"; from: -20; to: 0; duration: 350; easing.type: Easing.OutExpo }
                            }
                        }
                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0; duration: 250; easing.type: Easing.InCubic }
                                NumberAnimation { property: "scale"; to: 0.8; duration: 250; easing.type: Easing.InCubic }
                            }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "x,y"; duration: 300; easing.type: Easing.OutExpo }
                        }

                        spacing: 6
                        interactive: contentHeight > 320
                        model: taskModel

                        delegate: Rectangle {
                            width: taskListView.width
                            height: 42
                            radius: 9
                            color: model.done ? root.colSurfaceLow : root.colSurfaceHigh
                            border.color: model.done ? "transparent" : root.colOutlineVariant
                            border.width: 1
                            scale: taskHoverArea.containsMouse ? 1.015 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            MouseArea {
                                id: taskHoverArea
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: true
                                onClicked: mouse.accepted = false
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 10

                                Rectangle {
                                    width: 20
                                    height: 20
                                    radius: 6
                                    color: model.done ? root.colSuccess : "transparent"
                                    border.color: model.done ? root.colSuccess : root.colOutline
                                    border.width: 1.5

                                    Text {
                                        visible: model.done
                                        anchors.centerIn: parent
                                        text: "✓"
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: "#162319"
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleTask(model.rawIndex)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.text
                                    font.pixelSize: 13
                                    font.strikeout: model.done
                                    color: model.done ? root.colOutline : root.colText
                                    elide: Text.ElideRight

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleTask(model.rawIndex)
                                    }
                                }

                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 6
                                    color: itemDelMouse.containsMouse ? root.colSurfaceHighest : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: itemDelMouse.containsMouse ? root.colError : root.colOutline
                                    }
                                    MouseArea {
                                        id: itemDelMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.deleteTask(model.rawIndex)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: taskModel.count === 0
                        Layout.fillWidth: true
                        height: 32
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: root.activeFilter === "done" 
                                ? "No completed tasks yet" 
                                : (root.activeFilter === "active" ? "All done! ✦" : (root.activeCategory === "today" ? "No tasks for today" : "No daily habits added"))
                            font.pixelSize: 12
                            color: root.colOutline
                        }
                    }

                    // Task Input Field
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        TextField {
                            id: inputField
                            Layout.fillWidth: true
                            height: 36
                            placeholderText: root.activeCategory === "today" ? "Add task to Today..." : "Add daily habit..."
                            placeholderTextColor: root.colOutline
                            color: root.colText
                            font.pixelSize: 12
                            verticalAlignment: TextInput.AlignVCenter

                            background: Rectangle {
                                color: root.colSurfaceHigh
                                radius: 9
                                border.color: inputField.activeFocus ? (root.activeCategory === "today" ? root.colPrimary : root.colTertiary) : root.colOutlineVariant
                                border.width: 1
                            }
                            padding: 8

                            onAccepted: {
                                if (text.trim().length > 0) {
                                    root.addTask(text)
                                    text = ""
                                }
                            }
                        }

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 9
                            color: root.activeCategory === "today" ? root.colPrimary : root.colTertiary
                            Text {
                                anchors.centerIn: parent
                                text: "+"
                                font.pixelSize: 18
                                font.bold: true
                                color: root.activeCategory === "today" ? root.colTextOnPrimary : "#2a1526"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (inputField.text.trim().length > 0) {
                                        root.addTask(inputField.text)
                                        inputField.text = ""
                                    }
                                }
                            }
                        }
                    }
                }

                // ------------------------------------------
                // View 2: Agenda & Google Calendar
                // ------------------------------------------
                ColumnLayout {
                    id: agendaView
                    width: slidingContainer.width
                    spacing: 10
                    opacity: root.currentMainTab === "agenda" ? 1 : 0
                    visible: opacity > 0
                    x: root.currentMainTab === "agenda" ? 0 : slidingContainer.width

                    Behavior on x {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 180 }
                    }

                    // Filter row: Today | Upcoming | All + Sync Button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { "key": "today", "label": "Today" },
                                { "key": "upcoming", "label": "Upcoming" },
                                { "key": "all", "label": "All" }
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 26
                                radius: 8
                                color: root.agendaFilter === modelData.key ? root.colTertiary : root.colSurfaceHigh

                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: modelData.label
                                        font.pixelSize: 11
                                        font.bold: root.agendaFilter === modelData.key
                                        color: root.agendaFilter === modelData.key ? "#2a1526" : root.colText
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.agendaFilter = modelData.key
                                        root.syncAgendaModel()
                                    }
                                }
                            }
                        }

                        // Sync button (runs calendar_sync.py)
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 8
                            color: syncMouse.containsMouse ? root.colSurfaceHighest : root.colSurfaceHigh

                            Text {
                                anchors.centerIn: parent
                                text: "↻"
                                font.pixelSize: 14
                                font.bold: true
                                color: root.colTertiary
                            }
                            MouseArea {
                                id: syncMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: syncCalendarProc.running = true
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.colOutlineVariant
                    }

                    // Agenda Events List
                    ListView {
                        id: agendaListView
                        Layout.fillWidth: true
                        implicitHeight: Math.min(320, contentHeight)
                        clip: true
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 350; easing.type: Easing.OutExpo }
                                NumberAnimation { property: "x"; from: -20; to: 0; duration: 350; easing.type: Easing.OutExpo }
                            }
                        }
                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0; duration: 250; easing.type: Easing.InCubic }
                                NumberAnimation { property: "scale"; to: 0.8; duration: 250; easing.type: Easing.InCubic }
                            }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "x,y"; duration: 300; easing.type: Easing.OutExpo }
                        }

                        spacing: 6
                        interactive: contentHeight > 320
                        model: agendaModel

                        delegate: Rectangle {
                            width: agendaListView.width
                            height: 48
                            radius: 10
                            color: root.colSurfaceHigh
                            scale: agendaHoverArea.containsMouse ? 1.015 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            MouseArea {
                                id: agendaHoverArea
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: true
                                onClicked: mouse.accepted = false
                            }
                            border.color: model.isToday ? root.colTertiary : root.colOutlineVariant
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 8

                                // Time pill
                                Rectangle {
                                    width: 72
                                    height: 28
                                    radius: 6
                                    color: model.isToday ? "#382334" : root.colSurfaceLow

                                    Text {
                                        anchors.centerIn: parent
                                        text: model.time
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: model.isToday ? root.colTertiary : root.colTextVariant
                                    }
                                }

                                // Event Details
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: model.title
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: root.colText
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        spacing: 4
                                        Text {
                                            text: model.dateDisplay
                                            font.pixelSize: 10
                                            color: root.colOutline
                                        }
                                        Text {
                                            visible: model.location.length > 0
                                            text: "· " + model.location
                                            font.pixelSize: 10
                                            color: root.colPrimary
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // Delete option for local events
                                Rectangle {
                                    visible: model.source === "local"
                                    width: 20
                                    height: 20
                                    radius: 6
                                    color: evDelMouse.containsMouse ? root.colSurfaceHighest : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        font.pixelSize: 15
                                        color: root.colError
                                    }
                                    MouseArea {
                                        id: evDelMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            deleteLocalEventProc.eventId = model.eventId
                                            deleteLocalEventProc.running = true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Empty State for Agenda
                    Rectangle {
                        visible: agendaModel.count === 0
                        Layout.fillWidth: true
                        height: 40
                        color: "transparent"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "No events scheduled"
                                font.pixelSize: 12
                                color: root.colOutline
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Add an event below or sync Google Calendar"
                                font.pixelSize: 10
                                color: root.colTextVariant
                            }
                        }
                    }

                    // Quick Add Event Field
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        TextField {
                            id: eventTitleInput
                            Layout.fillWidth: true
                            height: 36
                            placeholderText: "New event (e.g. Team Sync)..."
                            placeholderTextColor: root.colOutline
                            color: root.colText
                            font.pixelSize: 12
                            verticalAlignment: TextInput.AlignVCenter

                            background: Rectangle {
                                color: root.colSurfaceHigh
                                radius: 9
                                border.color: eventTitleInput.activeFocus ? root.colTertiary : root.colOutlineVariant
                                border.width: 1
                            }
                            padding: 8

                            onAccepted: addEventBtn.onClicked()
                        }

                        TextField {
                            id: eventTimeInput
                            width: 80
                            height: 36
                            placeholderText: "10:00 AM"
                            placeholderTextColor: root.colOutline
                            color: root.colText
                            font.pixelSize: 11
                            verticalAlignment: TextInput.AlignVCenter

                            background: Rectangle {
                                color: root.colSurfaceHigh
                                radius: 9
                                border.color: eventTimeInput.activeFocus ? root.colTertiary : root.colOutlineVariant
                                border.width: 1
                            }
                            padding: 6

                            onAccepted: addEventBtn.onClicked()
                        }

                        Rectangle {
                            id: addEventBtn
                            width: 36
                            height: 36
                            radius: 9
                            color: root.colTertiary

                            signal clicked()
                            onClicked: {
                                if (eventTitleInput.text.trim().length > 0) {
                                    addLocalEventProc.eventTitle = eventTitleInput.text.trim()
                                    addLocalEventProc.eventTime = eventTimeInput.text.trim() || "All Day"
                                    addLocalEventProc.running = true
                                    eventTitleInput.text = ""
                                    eventTimeInput.text = ""
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "+"
                                font.pixelSize: 18
                                font.bold: true
                                color: "#2a1526"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: addEventBtn.clicked()
                            }
                        }
                    }
                }
            }
        }
    }
}
