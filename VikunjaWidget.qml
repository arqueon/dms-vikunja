import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets
import "."
import "./JS/vikunja.js" as Vikunja

PluginComponent {
    id: root

    property var popoutService: null
    readonly property var daemon: PluginService.pluginInstances["dmsVikunja"] ?? null
    readonly property var tasks: tasksGlobal.value || []
    readonly property var projects: projectsGlobal.value || []
    readonly property var labels: labelsGlobal.value || []
    readonly property bool configured: configuredGlobal.value === true
    readonly property bool isLoading: loadingGlobal.value === true
    readonly property bool isMutating: mutatingGlobal.value === true
    readonly property string errorMessage: String(errorGlobal.value || "")
    readonly property string operationMessage: String(operationGlobal.value || "")
    readonly property double lastUpdated: parseInt(updatedGlobal.value) || 0
    readonly property string detectedApiVersion: String(apiGlobal.value || "")
    readonly property string serverVersion: String(serverGlobal.value || "")
    readonly property var excludedProjectIds: Vikunja.toArray(pluginData.excludedProjectIds)
    readonly property bool showCompleted: pluginData.showCompleted === true
    readonly property string sortMode: String(pluginData.sortMode || "smart")
    readonly property int maxVisibleTasks: Math.max(25, parseInt(pluginData.maxVisibleTasks || "100"))
    readonly property bool hideWhenZero: pluginData.hideWhenZero === true
    readonly property var projectOptions: Vikunja.projectOptions(projects, false)
    readonly property var projectPaths: Vikunja.pathsById(projects)
    readonly property var effectiveExcluded: Vikunja.excludedSet(projects, excludedProjectIds)
    readonly property int openTaskCount: Vikunja.openCount(tasks, projects, excludedProjectIds)
    readonly property int urgentTaskCount: Vikunja.dueCount(tasks, projects, excludedProjectIds, Date.now())
    readonly property bool pillHidden: hideWhenZero && configured && openTaskCount === 0

    property string activeView: "tasks"
    property string searchQuery: ""
    property string labelQuery: ""
    property int activeProjectId: 0
    property int activeLabelId: 0
    property bool quickAddOpen: false
    property string quickTitle: ""
    property string quickDue: ""
    property int quickPriority: 0
    property int quickProjectId: 0
    property var quickLabelIds: []

    readonly property var filteredTasks: Vikunja.filterAndSortTasks(tasks, projects, {
        query: searchQuery,
        projectId: activeProjectId,
        labelId: activeLabelId,
        excludedProjectIds: excludedProjectIds,
        showCompleted: showCompleted,
        sortMode: sortMode
    })
    readonly property var displayedTasks: filteredTasks.slice(0, maxVisibleTasks)
    readonly property var filteredLabels: Vikunja.filterLabels(labels, labelQuery)

    pluginId: "dmsVikunja"
    pluginService: PluginService
    layerNamespacePlugin: "dms-vikunja"
    popoutWidth: 640
    popoutHeight: 680

    PluginGlobalVar {
        id: tasksGlobal
        varName: "tasks"
        defaultValue: []
    }

    PluginGlobalVar {
        id: projectsGlobal
        varName: "projects"
        defaultValue: []
    }

    PluginGlobalVar {
        id: labelsGlobal
        varName: "labels"
        defaultValue: []
    }

    PluginGlobalVar {
        id: configuredGlobal
        varName: "configured"
        defaultValue: false
    }

    PluginGlobalVar {
        id: loadingGlobal
        varName: "loading"
        defaultValue: false
    }

    PluginGlobalVar {
        id: mutatingGlobal
        varName: "mutating"
        defaultValue: false
    }

    PluginGlobalVar {
        id: errorGlobal
        varName: "errorMessage"
        defaultValue: ""
    }

    PluginGlobalVar {
        id: operationGlobal
        varName: "operationMessage"
        defaultValue: ""
    }

    PluginGlobalVar {
        id: updatedGlobal
        varName: "lastUpdated"
        defaultValue: 0
    }

    PluginGlobalVar {
        id: apiGlobal
        varName: "apiVersion"
        defaultValue: ""
    }

    PluginGlobalVar {
        id: serverGlobal
        varName: "serverVersion"
        defaultValue: ""
    }

    function saveSetting(key, value) {
        if (pluginService)
            pluginService.savePluginData(pluginId, key, value)
    }

    function refresh() {
        if (daemon)
            daemon.refresh()
    }

    function ensureQuickProject() {
        if (projectOptions.length === 0) {
            quickProjectId = 0
            return
        }
        if (activeProjectId > 0 && !effectiveExcluded[String(activeProjectId)]) {
            quickProjectId = activeProjectId
            return
        }
        var configuredDefault = parseInt(pluginData.defaultProjectId) || 0
        for (var i = 0; i < projectOptions.length; i++) {
            if (projectOptions[i].id === quickProjectId)
                return
            if (projectOptions[i].id === configuredDefault
                    && !effectiveExcluded[String(configuredDefault)]) {
                quickProjectId = configuredDefault
                return
            }
        }
        for (var j = 0; j < projectOptions.length; j++) {
            if (!effectiveExcluded[String(projectOptions[j].id)]) {
                quickProjectId = projectOptions[j].id
                return
            }
        }
        quickProjectId = projectOptions[0].id
    }

    function projectPathForId(projectId) {
        return String(projectPaths[String(parseInt(projectId) || 0)] || "Choose project")
    }

    function projectFromPath(path) {
        for (var i = 0; i < projectOptions.length; i++) {
            if (projectOptions[i].path === path)
                return projectOptions[i].id
        }
        return 0
    }

    function toggleQuickLabel(labelId) {
        var id = parseInt(labelId)
        var next = quickLabelIds.slice()
        var index = next.indexOf(id)
        if (index >= 0)
            next.splice(index, 1)
        else
            next.push(id)
        quickLabelIds = next
    }

    function createQuickTask() {
        if (!daemon || quickTitle.trim() === "" || quickProjectId <= 0)
            return
        var due = Vikunja.parseDueInput(quickDue)
        if (!due.ok) {
            ToastService?.showError("Vikunja", due.error)
            return
        }
        var apiDue = due.value === Vikunja.ZERO_DATE ? "" : due.value
        if (daemon.createTask(
                quickProjectId, quickTitle.trim(), apiDue,
                quickPriority, quickLabelIds.join(","))) {
            quickTitle = ""
            quickDue = ""
            quickPriority = 0
            quickLabelIds = []
            quickAddOpen = false
        }
    }

    function saveTask(taskId, title, description, done, percentDone,
                      dueText, priority, projectId, labelIds) {
        if (!daemon)
            return
        var due = Vikunja.parseDueInput(dueText)
        if (!due.ok) {
            ToastService?.showError("Vikunja", due.error)
            return
        }
        daemon.saveTask(taskId, JSON.stringify({
            title: title,
            description: description,
            done: done === true,
            percent_done: Number(percentDone) || 0,
            due_date: due.value,
            priority: priority,
            project_id: projectId
        }), Vikunja.toArray(labelIds).join(","))
    }

    function openTask(taskId) {
        var base = String(pluginData.baseUrl || "").replace(/\/+$/, "")
        if (base)
            Quickshell.execDetached(["xdg-open", base + "/tasks/" + taskId])
    }

    function toggleProjectIncluded(projectId) {
        var id = parseInt(projectId)
        var next = excludedProjectIds.slice()
        if (effectiveExcluded[String(id)]) {
            next = next.filter(function(excludedId) {
                return !Vikunja.descendantIds(projects, excludedId)[String(id)]
            })
        } else if (next.indexOf(id) === -1) {
            next.push(id)
        }
        saveSetting("excludedProjectIds", next)
    }

    function cycleSort() {
        var modes = ["smart", "due", "priority", "title", "project", "updated"]
        var next = (modes.indexOf(sortMode) + 1) % modes.length
        saveSetting("sortMode", modes[next])
    }

    function sortLabel(mode) {
        if (mode === "smart") return "Smart"
        if (mode === "due") return "Due date"
        if (mode === "priority") return "Priority"
        if (mode === "title") return "Title"
        if (mode === "project") return "Project"
        return "Recently updated"
    }

    function relativeUpdated() {
        if (!lastUpdated)
            return "never synced"
        var seconds = Math.floor((Date.now() - lastUpdated) / 1000)
        if (seconds < 60) return "synced just now"
        if (seconds < 3600) return "synced " + Math.floor(seconds / 60) + "m ago"
        return "synced " + Math.floor(seconds / 3600) + "h ago"
    }

    onProjectOptionsChanged: ensureQuickProject()
    onActiveProjectIdChanged: ensureQuickProject()

    horizontalBarPill: Component {
        Item {
            implicitWidth: root.pillHidden ? 0 : horizontalContent.implicitWidth
            implicitHeight: horizontalContent.implicitHeight
            visible: !root.pillHidden

            Row {
                id: horizontalContent
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter

                DankIcon {
                    name: root.errorMessage !== "" ? "sync_problem" : "task_alt"
                    size: root.iconSize
                    color: root.errorMessage !== "" ? Theme.error
                        : root.configured ? Theme.primary : Theme.surfaceVariantText
                }

                NumericText {
                    visible: root.openTaskCount > 0
                    text: root.openTaskCount > 99 ? "99+" : String(root.openTaskCount)
                    reserveText: "99+"
                    width: reservedWidth
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.primary
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: root.pillHidden ? 0 : verticalContent.implicitWidth
            implicitHeight: root.pillHidden ? 0 : verticalContent.implicitHeight
            visible: !root.pillHidden

            Column {
                id: verticalContent
                spacing: 1
                anchors.horizontalCenter: parent.horizontalCenter

                DankIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: root.errorMessage !== "" ? "sync_problem" : "task_alt"
                    size: root.iconSize
                    color: root.errorMessage !== "" ? Theme.error
                        : root.configured ? Theme.primary : Theme.surfaceVariantText
                }

                NumericText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.openTaskCount > 0
                    text: root.openTaskCount > 99 ? "99+" : String(root.openTaskCount)
                    reserveText: "99+"
                    width: reservedWidth
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.primary
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    pillRightClickAction: () => root.refresh()

    popoutContent: Component {
        PopoutComponent {
            id: popout
            width: root.popoutWidth
            headerText: "Vikunja"
            detailsText: {
                if (!root.configured)
                    return "Configure the server and API token in Settings → Plugins → dms-vikunja"
                if (root.errorMessage !== "")
                    return root.errorMessage
                var details = root.openTaskCount + " open"
                if (root.urgentTaskCount > 0)
                    details += " · " + root.urgentTaskCount + " due or overdue"
                details += " · " + root.relativeUpdated()
                if (root.serverVersion)
                    details += " · " + root.serverVersion + "/" + root.detectedApiVersion
                return details
            }
            showCloseButton: true
            closePopout: () => root.closePopout()

            headerActions: Component {
                Row {
                    spacing: Theme.spacingXS

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: addHeaderArea.containsMouse
                            ? Theme.withAlpha(Theme.primary, 0.22) : "transparent"

                        DankIcon {
                            anchors.centerIn: parent
                            name: "add_task"
                            size: 20
                            color: Theme.primary
                        }

                        MouseArea {
                            id: addHeaderArea
                            anchors.fill: parent
                            enabled: root.configured && !root.isMutating
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.activeView = "tasks"
                                root.quickAddOpen = !root.quickAddOpen
                                root.ensureQuickProject()
                            }
                        }
                    }

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: refreshHeaderArea.containsMouse
                            ? Theme.withAlpha(Theme.primary, 0.22) : "transparent"

                        DankIcon {
                            anchors.centerIn: parent
                            name: root.isLoading ? "sync" : "refresh"
                            size: 20
                            color: root.isLoading ? Theme.primary : Theme.surfaceText
                        }

                        MouseArea {
                            id: refreshHeaderArea
                            anchors.fill: parent
                            enabled: root.configured && !root.isLoading && !root.isMutating
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()
                        }
                    }
                }
            }

            Connections {
                target: popout.parentPopout
                function onOpened() {
                    if (root.configured && !root.isLoading
                            && (!root.lastUpdated || Date.now() - root.lastUpdated > 60000))
                        root.refresh()
                }
            }

            Item {
                id: popoutBody
                width: parent.width
                height: root.popoutHeight - popout.headerHeight - popout.detailsHeight

                Row {
                    id: navigation
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 40
                    spacing: Theme.spacingS

                    Repeater {
                        model: [
                            { id: "tasks", label: "Tasks", icon: "checklist" },
                            { id: "projects", label: "Projects", icon: "account_tree" },
                            { id: "labels", label: "Labels", icon: "label" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool selected: root.activeView === modelData.id
                            width: (navigation.width - Theme.spacingS * 2) / 3
                            height: 34
                            radius: Theme.cornerRadius
                            color: selected ? Theme.withAlpha(Theme.primary, 0.22)
                                : navArea.containsMouse ? Theme.surfaceContainerHigh
                                : "transparent"

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: modelData.icon
                                    size: 17
                                    color: parent.parent.selected ? Theme.primary : Theme.surfaceText
                                }

                                StyledText {
                                    text: modelData.label
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: parent.parent.selected ? Font.Bold : Font.Normal
                                    color: parent.parent.selected ? Theme.primary : Theme.surfaceText
                                }
                            }

                            MouseArea {
                                id: navArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeView = parent.modelData.id
                            }
                        }
                    }
                }

                Item {
                    id: mainArea
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: navigation.bottom
                    anchors.bottom: parent.bottom

                    Item {
                        anchors.fill: parent
                        visible: root.activeView === "tasks"

                        Column {
                            id: taskControls
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: Theme.spacingS

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                DankTextField {
                                    width: parent.width - 210 - Theme.spacingS * 2
                                    height: 38
                                    placeholderText: "Search tasks, projects, or labels"
                                    leftIconName: "search"
                                    text: root.searchQuery
                                    onTextChanged: root.searchQuery = text
                                }

                                Rectangle {
                                    width: 105
                                    height: 36
                                    radius: Theme.cornerRadius
                                    color: sortArea.containsMouse
                                        ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS
                                        DankIcon { name: "sort"; size: 16; color: Theme.surfaceText }
                                        StyledText {
                                            text: root.sortLabel(root.sortMode)
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceText
                                        }
                                    }

                                    MouseArea {
                                        id: sortArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.cycleSort()
                                    }
                                }

                                Rectangle {
                                    width: 105
                                    height: 36
                                    radius: Theme.cornerRadius
                                    color: root.showCompleted
                                        ? Theme.withAlpha(Theme.primary, 0.22)
                                        : completedArea.containsMouse
                                            ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS
                                        DankIcon {
                                            name: root.showCompleted ? "visibility" : "visibility_off"
                                            size: 16
                                            color: root.showCompleted ? Theme.primary : Theme.surfaceText
                                        }
                                        StyledText {
                                            text: "Completed"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: root.showCompleted ? Theme.primary : Theme.surfaceText
                                        }
                                    }

                                    MouseArea {
                                        id: completedArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.saveSetting("showCompleted", !root.showCompleted)
                                    }
                                }
                            }

                            Flow {
                                width: parent.width
                                visible: root.activeProjectId > 0 || root.activeLabelId > 0
                                spacing: Theme.spacingXS

                                Rectangle {
                                    visible: root.activeProjectId > 0
                                    width: activeProjectText.implicitWidth + Theme.spacingM * 2
                                    height: 28
                                    radius: 14
                                    color: Theme.withAlpha(Theme.primary, 0.2)
                                    StyledText {
                                        id: activeProjectText
                                        anchors.centerIn: parent
                                        text: root.projectPathForId(root.activeProjectId) + "  ×"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.primary
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activeProjectId = 0
                                    }
                                }

                                Rectangle {
                                    visible: root.activeLabelId > 0
                                    width: activeLabelText.implicitWidth + Theme.spacingM * 2
                                    height: 28
                                    radius: 14
                                    color: Theme.withAlpha(Theme.primary, 0.2)
                                    StyledText {
                                        id: activeLabelText
                                        anchors.centerIn: parent
                                        text: {
                                            for (var i = 0; i < root.labels.length; i++)
                                                if (parseInt(root.labels[i].id) === root.activeLabelId)
                                                    return String(root.labels[i].title || "Label") + "  ×"
                                            return "Label  ×"
                                        }
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.primary
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activeLabelId = 0
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                implicitHeight: root.quickAddOpen
                                    ? quickAddColumn.implicitHeight + Theme.spacingM * 2 : 0
                                height: implicitHeight
                                visible: root.quickAddOpen
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHigh

                                Column {
                                    id: quickAddColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.spacingM
                                    spacing: Theme.spacingS

                                    DankTextField {
                                        width: parent.width
                                        labelText: "New task"
                                        placeholderText: "What needs to be done?"
                                        text: root.quickTitle
                                        onTextChanged: root.quickTitle = text
                                    }

                                    ProjectPicker {
                                        width: parent.width
                                        options: root.projectOptions.filter(function(option) {
                                            return !root.effectiveExcluded[String(option.id)]
                                        })
                                        selectedId: root.quickProjectId
                                        onProjectSelected: projectId => root.quickProjectId = projectId
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        DueDatePicker {
                                            width: (parent.width - Theme.spacingS) * 0.62
                                            labelText: "Due date"
                                            value: root.quickDue
                                            onValueEdited: value => root.quickDue = value
                                        }

                                        DankDropdown {
                                            width: (parent.width - Theme.spacingS) * 0.38
                                            text: "Priority"
                                            options: ["No priority", "Low", "Medium", "High", "Urgent", "Do now"]
                                            currentValue: Vikunja.priorityLabel(root.quickPriority)
                                            onValueChanged: value => {
                                                var values = ["No priority", "Low", "Medium", "High", "Urgent", "Do now"]
                                                root.quickPriority = Math.max(0, values.indexOf(value))
                                            }
                                        }
                                    }

                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingXS

                                        Repeater {
                                            model: root.labels.slice(0, 30)

                                            delegate: Rectangle {
                                                required property var modelData
                                                readonly property bool selected:
                                                    root.quickLabelIds.indexOf(parseInt(modelData.id)) !== -1
                                                width: quickLabelText.implicitWidth + Theme.spacingM * 2
                                                height: 27
                                                radius: 14
                                                color: selected
                                                    ? Theme.withAlpha(
                                                        Vikunja.labelColor(modelData) || Theme.primary, 0.35)
                                                    : quickLabelArea.containsMouse
                                                        ? Theme.surfaceContainerHighest
                                                        : Theme.surfaceContainer

                                                StyledText {
                                                    id: quickLabelText
                                                    anchors.centerIn: parent
                                                    text: (parent.selected ? "✓ " : "")
                                                        + (modelData.title || "Label")
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: parent.selected ? Theme.primary : Theme.surfaceText
                                                }

                                                MouseArea {
                                                    id: quickLabelArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleQuickLabel(parent.modelData.id)
                                                }
                                            }
                                        }
                                    }

                                    Row {
                                        spacing: Theme.spacingS
                                        DankButton {
                                            text: root.isMutating ? "Saving…" : "Create task"
                                            iconName: "add_task"
                                            buttonHeight: 32
                                            enabled: !root.isMutating && root.quickTitle.trim() !== ""
                                                && root.quickProjectId > 0
                                            backgroundColor: Theme.primary
                                            textColor: Theme.primaryText
                                            onClicked: root.createQuickTask()
                                        }
                                        DankButton {
                                            text: "Cancel"
                                            buttonHeight: 32
                                            onClicked: root.quickAddOpen = false
                                        }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: taskList
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: taskControls.bottom
                            anchors.topMargin: Theme.spacingS
                            anchors.bottom: taskFooter.top
                            anchors.bottomMargin: Theme.spacingS
                            clip: true
                            spacing: Theme.spacingS
                            model: root.displayedTasks

                            delegate: TaskRow {
                                required property var modelData
                                width: taskList.width
                                task: modelData
                                projects: root.projects
                                projectOptions: root.projectOptions
                                projectPaths: root.projectPaths
                                labels: root.labels
                                busy: root.isMutating
                                onDoneRequested: (taskId, done) => {
                                    if (root.daemon) root.daemon.setDone(taskId, done)
                                }
                                onSaveRequested: (taskId, title, description, done,
                                                  percentDone, dueText, priority,
                                                  projectId, labelIds) =>
                                    root.saveTask(taskId, title, description, done,
                                                  percentDone, dueText, priority,
                                                  projectId, labelIds)
                                onDeleteRequested: taskId => {
                                    if (root.daemon) root.daemon.deleteTask(taskId)
                                }
                                onAttachmentsRequested: (taskId, fileUrls) => {
                                    if (root.daemon)
                                        root.daemon.uploadAttachments(
                                            taskId, JSON.stringify(fileUrls))
                                }
                                onOpenRequested: taskId => root.openTask(taskId)
                            }

                            StyledText {
                                anchors.centerIn: parent
                                visible: root.configured && !root.isLoading
                                    && root.displayedTasks.length === 0
                                text: root.filteredTasks.length === 0
                                    ? "No tasks match this view" : "No tasks"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                            }
                        }

                        StyledText {
                            id: taskFooter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 24
                            text: {
                                if (!root.configured) return "Open plugin settings to connect Vikunja"
                                if (root.isLoading) return "Synchronizing…"
                                if (root.isMutating) return "Applying task operation…"
                                if (root.filteredTasks.length > root.displayedTasks.length)
                                    return "Showing " + root.displayedTasks.length + " of " + root.filteredTasks.length
                                if (root.operationMessage) return root.operationMessage
                                return root.filteredTasks.length + " task" + (root.filteredTasks.length === 1 ? "" : "s")
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.errorMessage !== "" ? Theme.error : Theme.surfaceVariantText
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: root.activeView === "projects"

                        StyledText {
                            id: projectHelp
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 42
                            text: "Uncheck a project to exclude its tasks. Parent exclusions also apply to nested projects. Click a name to filter the task view."
                            wrapMode: Text.WordWrap
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        ListView {
                            id: projectList
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: projectHelp.bottom
                            anchors.bottom: parent.bottom
                            clip: true
                            spacing: Theme.spacingXS
                            model: root.projectOptions

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool included:
                                    !root.effectiveExcluded[String(modelData.id)]
                                width: projectList.width
                                height: 44
                                radius: Theme.cornerRadius
                                color: projectNameArea.containsMouse
                                    ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                Rectangle {
                                    id: projectCheck
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    height: 24
                                    radius: 5
                                    color: parent.included
                                        ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                                    border.width: 2
                                    border.color: parent.included ? Theme.primary : Theme.surfaceVariantText

                                    DankIcon {
                                        anchors.centerIn: parent
                                        visible: parent.parent.included
                                        name: "check"
                                        size: 16
                                        color: Theme.primary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleProjectIncluded(parent.parent.modelData.id)
                                    }
                                }

                                StyledText {
                                    anchors.left: projectCheck.right
                                    anchors.leftMargin: Theme.spacingM + modelData.depth * Theme.spacingL
                                    anchors.right: projectCount.left
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.title
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: parent.included ? Theme.surfaceText : Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    id: projectCount
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(Vikunja.filterAndSortTasks(root.tasks, root.projects, {
                                        projectId: modelData.id,
                                        excludedProjectIds: [],
                                        showCompleted: root.showCompleted,
                                        sortMode: "title"
                                    }).length)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                MouseArea {
                                    id: projectNameArea
                                    anchors.left: projectCheck.right
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.activeProjectId = parent.modelData.id
                                        root.activeView = "tasks"
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: root.activeView === "labels"

                        StyledText {
                            id: labelHelp
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: implicitHeight
                            text: "Filter the list, then select a label to see its tasks across every included project."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        DankTextField {
                            id: labelFilter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: labelHelp.bottom
                            anchors.topMargin: Theme.spacingS
                            labelText: "Filter labels"
                            placeholderText: "Type a label name"
                            text: root.labelQuery
                            onTextChanged: root.labelQuery = text
                        }

                        ListView {
                            id: labelList
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: labelFilter.bottom
                            anchors.topMargin: Theme.spacingS
                            anchors.bottom: parent.bottom
                            clip: true
                            spacing: Theme.spacingXS
                            model: root.filteredLabels

                            StyledText {
                                anchors.centerIn: parent
                                visible: root.filteredLabels.length === 0
                                text: root.labelQuery.trim() === ""
                                    ? "No labels available" : "No labels match this filter"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                            }

                            delegate: Rectangle {
                                required property var modelData
                                width: labelList.width
                                height: 44
                                radius: Theme.cornerRadius
                                color: parseInt(modelData.id) === root.activeLabelId
                                    ? Theme.withAlpha(Theme.primary, 0.2)
                                    : labelArea.containsMouse
                                        ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                border.width: parseInt(modelData.id) === root.activeLabelId ? 1 : 0
                                border.color: Theme.primary

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: Vikunja.labelColor(modelData) || Theme.primary
                                }

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM + 28
                                    anchors.right: labelTaskCount.left
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (parseInt(modelData.id) === root.activeLabelId ? "✓ " : "")
                                        + String(modelData.title || "Label")
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    id: labelTaskCount
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(Vikunja.labelCount(
                                        root.tasks, modelData.id, root.projects,
                                        root.excludedProjectIds, root.showCompleted))
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                MouseArea {
                                    id: labelArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.activeLabelId = parseInt(parent.modelData.id)
                                        root.activeView = "tasks"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ccWidgetIcon: "task_alt"
    ccWidgetPrimaryText: "Vikunja"
    ccWidgetSecondaryText: !configured ? "Not configured"
        : errorMessage !== "" ? "Sync error"
        : openTaskCount + " open · " + urgentTaskCount + " urgent"
    ccWidgetIsActive: configured && errorMessage === ""
    onCcWidgetToggled: root.triggerPopout()
}
