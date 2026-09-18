import QtQuick.Controls 2.15
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
    implicitHeight: Math.min(640, mainCard.implicitHeight)
// Restore dynamic sizing!

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
    property bool nextTaskIsDaily: false
    property string activeFilter: "all"     // "all" | "active" | "done"
    property var masterList: []
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
        command: ["bash", "-c", "mkdir -p ~/.local/state && touch ~/.local/state/todos.json"]
        running: true
        onExited: {
            readProc.running = true
            syncCalendarProc.running = true
        }
    }

    Process {
        id: readProc
        command: ["bash", "-c", "cat ~/.local/state/todos.json | tr -d '\n'"]
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim().length > 0) {
                    try {
                        var parsed = JSON.parse(data)
                        var curDate = root.getTodayString()

                        if (Array.isArray(parsed)) {
                            root.masterList = parsed.map(t => ({text: t.text || t, done: t.done || false, type: t.type || "today"}))
                            root.lastResetDate = curDate
                        } else {
                            var m = []
                            if (Array.isArray(parsed.today)) {
                                m = m.concat(parsed.today.map(t => ({text: t.text, done: t.done, type: "today"})))
                            }
                            if (Array.isArray(parsed.daily)) {
                                m = m.concat(parsed.daily.map(t => ({text: t.text, done: t.done, type: "daily"})))
                            }
                            root.masterList = m
                            root.lastResetDate = parsed.lastResetDate || curDate

                            if (root.lastResetDate !== curDate) {
                                var newList = []
                                for (var i = 0; i < root.masterList.length; i++) {
                                    var t = root.masterList[i]
                                    if (t.type === "daily") {
                                        t.done = false
                                        newList.push(t)
                                    } else {
                                        if (!t.done) {
                                            newList.push(t)
                                        }
                                    }
                                }
                                root.masterList = newList
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
        command: ["bash", "-c", "cat << 'EOF' > ~/.local/state/todos.json\n" + content + "\nEOF"]
    }

    function saveTodos() {
        var payload = {
            "lastResetDate": lastResetDate || getTodayString(),
            "master": masterList
        }
        writeProc.content = JSON.stringify(masterList, null, 2)
        writeProc.running = true
    }

    function syncTaskModel() {
        taskModel.clear()
        for (var i = 0; i < masterList.length; i++) {
            var item = masterList[i]
            var matches = true
            if (activeFilter === "active" && item.done) matches = false
            if (activeFilter === "done" && !item.done) matches = false

            if (matches) {
                taskModel.append({
                    "text": item.text,
                    "done": item.done,
                    "rawIndex": i,
                    "type": item.type || "today"
                })
            }
        }
    }

    function toggleTask(rawIndex) {
        if (rawIndex >= 0 && rawIndex < masterList.length) {
            var temp = masterList
            temp[rawIndex].done = !temp[rawIndex].done
            masterList = temp
            saveTodos()
            syncTaskModel()
        }
    }

    function deleteTask(rawIndex) {
        console.log("deleteTask triggered! rawIndex: " + rawIndex)
        if (rawIndex >= 0 && rawIndex < masterList.length) {
            var temp = masterList
            temp.splice(rawIndex, 1)
            masterList = temp
            saveTodos()
            syncTaskModel()
        }
    }

    function addTask(text, type) {
        console.log("addTask triggered! text: " + text + " type: " + type)
        var temp = masterList
        temp.push({"text": text, "done": false, "type": type})
        masterList = temp
        saveTodos()
        syncTaskModel()
    }


    function countPending() {
        var c = 0
        for (var i = 0; i < masterList.length; i++) {
            if (!masterList[i].done) c++
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
        command: ["bash", "-c", "cat ~/.local/state/calendar_events.json | tr -d '\n'"]
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
        command: ["python3", "-c", "import json, os, datetime; f=os.path.expanduser('~/.local/state/calendar_local.json'); data=json.load(open(f)) if os.path.exists(f) else []; data.append({'id': int(datetime.datetime.now().timestamp()), 'title': '" + eventTitle + "', 'date': datetime.datetime.now().strftime('%Y-%m-%d'), 'time': '" + eventTime + "'}); json.dump(data, open(f, 'w'), indent=2)"]
        onExited: syncCalendarProc.running = true
    }

    Process {
        id: deleteLocalEventProc
        property int eventId: 0
        command: ["python3", "-c", "import json, os; f=os.path.expanduser('~/.local/state/calendar_local.json'); data=[x for x in json.load(open(f)) if x.get('id') != " + eventId + "] if os.path.exists(f) else []; json.dump(data, open(f, 'w'), indent=2)"]
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
        implicitHeight: cardLayout.implicitHeight + 28
        radius: 20
        color: root.colSurface
        border.color: root.colOutlineVariant
        border.width: 1

        ColumnLayout {
            id: cardLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
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
                    Rectangle {
                        color: "transparent"
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
                                    text: String(root.countPending())
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.currentMainTab === "tasks" ? root.colPrimary : root.colTextVariant
                                }
                            }
                        }

                        TapHandler {
                            onTapped: root.currentMainTab = "tasks"
                        }
                    }

                    // Agenda / Calendar Tab Pill
                    Rectangle {
                        color: "transparent"
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

                        TapHandler {
                            onTapped: {
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
                                TapHandler {
                                    onTapped: {
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
                    // Super Cool Empty State
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 180
                        visible: taskModel.count === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                id: emptyIconTasks
                                text: "task_alt"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 56
                                color: root.colPrimary
                                Layout.alignment: Qt.AlignHCenter
                                
                                property real floatOffset: 0
                                NumberAnimation on floatOffset {
                                    from: 0; to: 2 * Math.PI; duration: 3000; loops: Animation.Infinite
                                }
                                transform: Translate {
                                    y: Math.sin(emptyIconTasks.floatOffset) * 6
                                }
                                
                                layer.enabled: true
                                // We don't have DropShadow imported by default so we just use the glow color
                            }
                            
                            Text {
                                text: "You're all caught up!"
                                font.pixelSize: 15
                                font.bold: true
                                color: root.colText
                                Layout.alignment: Qt.AlignHCenter
                            }
                            
                            Text {
                                text: "Enjoy the peace, or add a new task below."
                                font.pixelSize: 12
                                color: root.colTextVariant
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }



                    // Task List View
                    ListView {
                        id: taskListView
                        Layout.fillWidth: true
                        implicitHeight: Math.min(320, contentHeight)
                        visible: taskModel.count > 0
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

                        delegate: Item {
                            id: taskItemWrapper
                            width: taskListView.width
                            height: 42
                            clip: true

                            // Underneath: Red Slide-to-Delete background reveal
                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: root.colError
                                opacity: Math.min(1.0, Math.abs(taskCard.x) / 60)

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Text {
                                        text: "delete"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 18
                                        color: "#2a1526"
                                    }
                                    Text {
                                        text: taskCard.x < -80 ? "Release to delete" : "Slide to delete"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: "#2a1526"
                                    }
                                }
                            }

                            // Top: Draggable Task Card
                            Rectangle {
                                id: taskCard
                                width: parent.width
                                height: parent.height
                                radius: 9
                                color: taskHover.hovered ? root.colSurfaceHighest : (model.done ? root.colSurfaceLow : root.colSurfaceHigh)
                                border.color: taskHover.hovered ? root.colOutline : (model.done ? "transparent" : root.colOutlineVariant)
                                border.width: 1

                                DragHandler {
                                    id: dragHandler
                                    target: taskCard
                                    xAxis.maximum: 0
                                    xAxis.minimum: -taskItemWrapper.width
                                    yAxis.enabled: false

                                    onActiveChanged: {
                                        if (!active) {
                                            if (taskCard.x < -80) {
                                                deleteAnim.start()
                                            } else {
                                                snapAnim.start()
                                            }
                                        }
                                    }
                                }

                                NumberAnimation {
                                    id: snapAnim
                                    target: taskCard
                                    property: "x"
                                    to: 0
                                    duration: 220
                                    easing.type: Easing.OutBack
                                }

                                SequentialAnimation {
                                    id: deleteAnim
                                    ParallelAnimation {
                                        NumberAnimation { target: taskCard; property: "x"; to: -taskItemWrapper.width; duration: 180; easing.type: Easing.InQuad }
                                        NumberAnimation { target: taskCard; property: "opacity"; to: 0; duration: 180 }
                                    }
                                    ScriptAction {
                                        script: root.deleteTask(model.rawIndex)
                                    }
                                }

                                HoverHandler { id: taskHover }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 14
                                    spacing: 10

                                    // Checkbox
                                    Rectangle {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
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
                                        TapHandler {
                                            onTapped: root.toggleTask(model.rawIndex)
                                        }
                                    }

                                    // Daily recurring toggle badge
                                    Rectangle {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        radius: 4
                                        color: model.type === "daily" ? Qt.alpha(root.colTertiary, 0.2) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "↻"
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: model.type === "daily" ? root.colTertiary : root.colOutlineVariant
                                        }
                                        TapHandler {
                                            onTapped: root.toggleRecurring(model.rawIndex)
                                        }
                                    }

                                    // Task Title
                                    Text {
                                        Layout.fillWidth: true
                                        text: model.text
                                        font.pixelSize: 13
                                        font.strikeout: model.done
                                        color: model.done ? root.colOutline : root.colText
                                        elide: Text.ElideRight

                                        TapHandler {
                                            onTapped: root.toggleTask(model.rawIndex)
                                        }
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
                                : (root.activeFilter === "active" ? "All done! ✦" : "No tasks added")
                            font.pixelSize: 12
                            color: root.colOutline
                        }
                    }

                    // Task Input Field (Clean, Enter to add)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        TextField {
                            id: inputField
                            Layout.fillWidth: true
                            height: 36
                            placeholderText: root.nextTaskIsDaily ? "Add daily habit... (Press Enter)" : "Add task... (Press Enter)"
                            placeholderTextColor: root.colOutline
                            color: root.colText
                            font.pixelSize: 12
                            verticalAlignment: TextInput.AlignVCenter

                            background: Rectangle {
                                color: root.colSurfaceHigh
                                radius: 10
                                border.color: inputField.activeFocus ? (root.nextTaskIsDaily ? root.colTertiary : root.colPrimary) : root.colOutlineVariant
                                border.width: 1
                            }
                            padding: 10

                            onAccepted: {
                                if (text.trim().length > 0) {
                                    root.addTask(text.trim(), root.nextTaskIsDaily ? "daily" : "today")
                                    text = ""
                                }
                            }
                        }

                        // Daily recurring toggle
                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 10
                            color: root.nextTaskIsDaily ? root.colTertiary : (repBtnHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh)
                            border.color: root.nextTaskIsDaily ? "transparent" : root.colOutlineVariant
                            border.width: 1

                            HoverHandler { id: repBtnHover }
                            TapHandler {
                                onTapped: root.nextTaskIsDaily = !root.nextTaskIsDaily
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "↻"
                                font.pixelSize: 18
                                font.bold: true
                                color: root.nextTaskIsDaily ? root.colSurfaceHighest : (repBtnHover.hovered ? root.colText : root.colOutline)
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
                                TapHandler {
                                    onTapped: {
                                        root.agendaFilter = modelData.key
                                        root.syncAgendaModel()
                                    }
                                }
                            }
                        }

                        // Sync button
                        Rectangle {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: 8
                            color: syncHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh

                            HoverHandler { id: syncHover }
                            TapHandler {
                                onTapped: syncCalendarProc.running = true
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "↻"
                                font.pixelSize: 14
                                font.bold: true
                                color: root.colTertiary
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

                        delegate: Item {
                            id: eventItemWrapper
                            width: agendaListView.width
                            height: 48
                            clip: true

                            // Underneath: Red Slide-to-Delete reveal for local events
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: root.colError
                                visible: model.source === "local"
                                opacity: Math.min(1.0, Math.abs(eventCard.x) / 60)

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Text {
                                        text: "delete"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 18
                                        color: "#2a1526"
                                    }
                                    Text {
                                        text: eventCard.x < -80 ? "Release to delete" : "Slide to delete"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: "#2a1526"
                                    }
                                }
                            }

                            // Top: Event Card
                            Rectangle {
                                id: eventCard
                                width: parent.width
                                height: parent.height
                                radius: 10
                                color: eventHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh
                                border.color: model.isToday ? root.colTertiary : root.colOutlineVariant
                                border.width: 1

                                DragHandler {
                                    id: eventDragHandler
                                    enabled: model.source === "local"
                                    target: eventCard
                                    xAxis.maximum: 0
                                    xAxis.minimum: -eventItemWrapper.width
                                    yAxis.enabled: false

                                    onActiveChanged: {
                                        if (!active) {
                                            if (eventCard.x < -80) {
                                                deleteEventAnim.start()
                                            } else {
                                                snapEventAnim.start()
                                            }
                                        }
                                    }
                                }

                                NumberAnimation {
                                    id: snapEventAnim
                                    target: eventCard
                                    property: "x"
                                    to: 0
                                    duration: 220
                                    easing.type: Easing.OutBack
                                }

                                SequentialAnimation {
                                    id: deleteEventAnim
                                    ParallelAnimation {
                                        NumberAnimation { target: eventCard; property: "x"; to: -eventItemWrapper.width; duration: 180; easing.type: Easing.InQuad }
                                        NumberAnimation { target: eventCard; property: "opacity"; to: 0; duration: 180 }
                                    }
                                    ScriptAction {
                                        script: {
                                            deleteLocalEventProc.eventId = model.eventId
                                            deleteLocalEventProc.running = true
                                        }
                                    }
                                }

                                HoverHandler { id: eventHover }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    // Time pill
                                    Rectangle {
                                        Layout.preferredWidth: 68
                                        Layout.preferredHeight: 28
                                        radius: 7
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
                                        spacing: 2

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

                    // Quick Add Event Field (Press Enter to Add!)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        function triggerAddEvent() {
                            if (eventTitleInput.text.trim().length > 0) {
                                addLocalEventProc.eventTitle = eventTitleInput.text.trim()
                                addLocalEventProc.eventTime = eventTimeInput.text.trim() || "All Day"
                                addLocalEventProc.running = true
                                eventTitleInput.text = ""
                                eventTimeInput.text = ""
                            }
                        }

                        TextField {
                            id: eventTitleInput
                            Layout.fillWidth: true
                            height: 36
                            placeholderText: "Event title... (Press Enter)"
                            placeholderTextColor: root.colOutline
                            color: root.colText
                            font.pixelSize: 12
                            verticalAlignment: TextInput.AlignVCenter

                            background: Rectangle {
                                color: root.colSurfaceHigh
                                radius: 10
                                border.color: eventTitleInput.activeFocus ? root.colTertiary : root.colOutlineVariant
                                border.width: 1
                            }
                            padding: 10

                            onAccepted: parent.triggerAddEvent()
                        }

                        TextField {
                            id: eventTimeInput
                            Layout.preferredWidth: 85
                            Layout.preferredHeight: 36
                            placeholderText: "Time (opt)"
                            placeholderTextColor: root.colOutline
                            color: root.colText
                            font.pixelSize: 11
                            verticalAlignment: TextInput.AlignVCenter

                            background: Rectangle {
                                color: root.colSurfaceHigh
                                radius: 10
                                border.color: eventTimeInput.activeFocus ? root.colTertiary : root.colOutlineVariant
                                border.width: 1
                            }
                            padding: 8

                            onAccepted: parent.triggerAddEvent()
                        }
                    }
                }
            }
        }
    }
}
