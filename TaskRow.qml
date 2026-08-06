import QtQuick
import qs.Common
import qs.Widgets
import "."
import "./JS/vikunja.js" as Vikunja

Item {
    id: root

    required property var task
    property var projects: []
    property var projectOptions: []
    property var labels: []
    property var projectPaths: ({})
    property bool busy: false

    property bool expanded: false
    property bool editing: false
    property bool deleteArmed: false
    property string editTitle: ""
    property string editDescription: ""
    property string editDescriptionOriginal: ""
    property bool editDone: false
    property real editPercentDone: 0
    property string editDue: ""
    property int editPriority: 0
    property int editProjectId: 0
    property var editLabelIds: []

    signal doneRequested(int taskId, bool done)
    signal saveRequested(int taskId, string title, string description,
                         bool done, real percentDone,
                         string dueText, int priority, int projectId, var labelIds)
    signal deleteRequested(int taskId)
    signal openRequested(int taskId)
    signal attachmentsRequested(int taskId, var fileUrls)

    implicitHeight: card.implicitHeight

    function syncEditor() {
        editTitle = String(task.title || "")
        editDescriptionOriginal = String(task.description || "")
        editDescription = Vikunja.plainText(editDescriptionOriginal)
        editDone = task.done === true
        editPercentDone = Number(task.percent_done) || 0
        editDue = Vikunja.dueInput(task)
        editPriority = parseInt(task.priority) || 0
        editProjectId = parseInt(task.project_id) || 0
        editLabelIds = Vikunja.labelIds(task)
    }

    function descriptionForSave() {
        return editDescription === Vikunja.plainText(editDescriptionOriginal)
            ? editDescriptionOriginal : Vikunja.contentHtml(editDescription)
    }

    function projectPathForId(projectId) {
        return String(projectPaths[String(parseInt(projectId) || 0)] || "Unknown project")
    }

    function labelSelected(labelId) {
        return editLabelIds.indexOf(parseInt(labelId)) !== -1
    }

    function toggleLabel(labelId) {
        var id = parseInt(labelId)
        var next = editLabelIds.slice()
        var index = next.indexOf(id)
        if (index >= 0)
            next.splice(index, 1)
        else
            next.push(id)
        editLabelIds = next
    }

    function requestDelete() {
        if (!deleteArmed) {
            deleteArmed = true
            deleteConfirmTimer.restart()
            return
        }
        deleteConfirmTimer.stop()
        deleteArmed = false
        deleteRequested(parseInt(task.id))
    }

    Component.onCompleted: syncEditor()
    onTaskChanged: syncEditor()

    Timer {
        id: deleteConfirmTimer
        interval: 3500
        repeat: false
        onTriggered: root.deleteArmed = false
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: taskColumn.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: taskMouse.containsMouse || root.expanded
            ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        border.width: root.expanded ? 1 : 0
        border.color: Theme.withAlpha(Theme.primary, 0.45)

        Column {
            id: taskColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            Row {
                width: parent.width
                spacing: Theme.spacingS

                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: doneArea.containsMouse
                        ? Theme.withAlpha(Theme.primary, 0.28) : "transparent"
                    border.width: 2
                    border.color: root.task.done === true
                        ? Theme.primary : Theme.surfaceVariantText

                    DankIcon {
                        anchors.centerIn: parent
                        visible: root.task.done === true
                        name: "check"
                        size: 17
                        color: Theme.primary
                    }

                    MouseArea {
                        id: doneArea
                        anchors.fill: parent
                        enabled: !root.busy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.doneRequested(
                            parseInt(root.task.id), root.task.done !== true)
                    }
                }

                Column {
                    width: parent.width - 26 - 36 - Theme.spacingS * 2
                    spacing: 2

                    StyledText {
                        width: parent.width
                        text: String(root.task.title || "Untitled task")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        font.strikeout: root.task.done === true
                        color: root.task.done === true
                            ? Theme.surfaceVariantText : Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: {
                            var parts = []
                            var identifier = String(root.task.identifier || "")
                            if (identifier)
                                parts.push(identifier)
                            parts.push(root.projectPathForId(root.task.project_id))
                            if ((parseInt(root.task.priority) || 0) > 0)
                                parts.push(Vikunja.priorityLabel(root.task.priority))
                            return parts.join(" · ")
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        color: (parseInt(root.task.priority) || 0) >= 4
                            ? Theme.error : Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        visible: Vikunja.dueTimestamp(root.task) > 0
                        width: parent.width
                        text: Vikunja.formatDue(root.task, Date.now())
                        font.pixelSize: Theme.fontSizeSmall
                        color: {
                            var state = Vikunja.dueState(root.task, Date.now())
                            return state === "overdue" ? Theme.error
                                : state === "today" ? Theme.primary
                                : Theme.surfaceVariantText
                        }
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: 36
                    height: 32
                    radius: Theme.cornerRadius
                    anchors.verticalCenter: parent.verticalCenter
                    color: expandArea.containsMouse
                        ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.expanded ? "expand_less" : "expand_more"
                        size: 20
                        color: Theme.surfaceText
                    }

                    MouseArea {
                        id: expandArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.expanded = !root.expanded
                            if (!root.expanded) {
                                root.editing = false
                                root.deleteArmed = false
                            }
                        }
                    }
                }
            }

            Flow {
                width: parent.width
                visible: !root.editing && Vikunja.toArray(root.task.labels).length > 0
                spacing: Theme.spacingXS

                Repeater {
                    model: Vikunja.toArray(root.task.labels).slice(0, 5)

                    delegate: Rectangle {
                        required property var modelData
                        width: displayLabel.implicitWidth + Theme.spacingS * 2
                        height: 22
                        radius: 11
                        color: Vikunja.labelColor(modelData) !== ""
                            ? Theme.withAlpha(Vikunja.labelColor(modelData), 0.25)
                            : Theme.surfaceContainer

                        StyledText {
                            id: displayLabel
                            anchors.centerIn: parent
                            text: modelData.title || "Label"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                    }
                }
            }

            Column {
                width: parent.width
                visible: root.expanded && !root.editing
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width
                    visible: String(root.task.description || "").trim() !== ""
                    text: Vikunja.plainText(root.task.description || "")
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 6
                    elide: Text.ElideRight
                }

                Row {
                    spacing: Theme.spacingS

                    DankButton {
                        text: "Edit"
                        iconName: "edit"
                        buttonHeight: 30
                        enabled: !root.busy
                        onClicked: {
                            root.syncEditor()
                            root.editing = true
                        }
                    }

                    DankButton {
                        text: "Open"
                        iconName: "open_in_new"
                        buttonHeight: 30
                        onClicked: root.openRequested(parseInt(root.task.id))
                    }

                    DankButton {
                        text: root.deleteArmed ? "Confirm delete" : "Delete"
                        iconName: "delete"
                        buttonHeight: 30
                        enabled: !root.busy
                        backgroundColor: root.deleteArmed
                            ? Theme.error : Theme.withAlpha(Theme.error, 0.16)
                        textColor: root.deleteArmed ? Theme.errorText : Theme.error
                        onClicked: root.requestDelete()
                    }
                }
            }

            Column {
                width: parent.width
                visible: root.expanded && root.editing
                spacing: Theme.spacingS

                DankTextField {
                    width: parent.width
                    labelText: "Title"
                    text: root.editTitle
                    onTextChanged: root.editTitle = text
                }

                ContentEditor {
                    width: parent.width
                    text: root.editDescription
                    onTextChanged: root.editDescription = text
                }

                DankDropdown {
                    width: parent.width
                    text: "Status / progress"
                    options: {
                        var values = [
                            "To do",
                            "In progress · 25%",
                            "In progress · 50%",
                            "In progress · 75%",
                            "Completed"
                        ]
                        var current = Vikunja.statusLabel(
                            root.editDone, root.editPercentDone)
                        if (values.indexOf(current) === -1)
                            values.splice(1, 0, current)
                        return values
                    }
                    currentValue: Vikunja.statusLabel(
                        root.editDone, root.editPercentDone)
                    onValueChanged: value => {
                        var state = Vikunja.statusState(value)
                        root.editDone = state.done
                        root.editPercentDone = state.percentDone
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DueDatePicker {
                        width: (parent.width - Theme.spacingS) * 0.56
                        value: root.editDue
                        onValueEdited: value => root.editDue = value
                    }

                    DankDropdown {
                        width: (parent.width - Theme.spacingS) * 0.44
                        text: "Priority"
                        options: ["No priority", "Low", "Medium", "High", "Urgent", "Do now"]
                        currentValue: Vikunja.priorityLabel(root.editPriority)
                        onValueChanged: value => {
                            var values = ["No priority", "Low", "Medium", "High", "Urgent", "Do now"]
                            root.editPriority = Math.max(0, values.indexOf(value))
                        }
                    }
                }

                ProjectPicker {
                    width: parent.width
                    options: root.projectOptions
                    selectedId: root.editProjectId
                    onProjectSelected: projectId => root.editProjectId = projectId
                }

                AttachmentPanel {
                    width: parent.width
                    attachments: Vikunja.toArray(root.task.attachments)
                    busy: root.busy
                    onUploadRequested: fileUrls => root.attachmentsRequested(
                        parseInt(root.task.id), fileUrls)
                }

                StyledText {
                    width: parent.width
                    text: "Labels"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                Flow {
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: root.labels

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool selected: root.labelSelected(modelData.id)
                            width: editLabel.implicitWidth + Theme.spacingM * 2
                            height: 28
                            radius: 14
                            color: selected
                                ? Theme.withAlpha(
                                    Vikunja.labelColor(modelData) || Theme.primary, 0.35)
                                : editLabelArea.containsMouse
                                    ? Theme.surfaceContainerHighest
                                    : Theme.surfaceContainer

                            StyledText {
                                id: editLabel
                                anchors.centerIn: parent
                                text: (parent.selected ? "✓ " : "") + (modelData.title || "Label")
                                font.pixelSize: Theme.fontSizeSmall
                                color: parent.selected ? Theme.primary : Theme.surfaceText
                            }

                            MouseArea {
                                id: editLabelArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleLabel(parent.modelData.id)
                            }
                        }
                    }
                }

                Row {
                    spacing: Theme.spacingS

                    DankButton {
                        text: "Save"
                        iconName: "check"
                        buttonHeight: 32
                        enabled: !root.busy && root.editTitle.trim() !== ""
                        backgroundColor: Theme.primary
                        textColor: Theme.primaryText
                        onClicked: root.saveRequested(
                            parseInt(root.task.id), root.editTitle.trim(),
                            root.descriptionForSave(), root.editDone,
                            root.editPercentDone, root.editDue, root.editPriority,
                            root.editProjectId, root.editLabelIds)
                    }

                    DankButton {
                        text: "Cancel"
                        buttonHeight: 32
                        onClicked: {
                            root.syncEditor()
                            root.editing = false
                        }
                    }
                }
            }
        }

        MouseArea {
            id: taskMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }
}
