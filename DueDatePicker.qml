import QtQuick
import QtQuick.Controls
import QtQuick.Window
import qs.Common
import qs.Widgets
import "./JS/vikunja.js" as Vikunja

Item {
    id: root

    property string value: ""
    property string labelText: "Due date"
    property int firstDayOfWeek: 0
    property date selectedDate: new Date()
    property date displayDate: new Date()
    property string timeText: "23:59"
    property string validationError: ""
    property bool openUpwards: false

    signal valueEdited(string value)

    readonly property int cellSize: 36

    height: 48

    function syncFromValue() {
        var parsed = Vikunja.parseDueInput(value)
        var date
        if (parsed.ok && parsed.value !== Vikunja.ZERO_DATE) {
            date = new Date(parsed.value)
        } else {
            date = new Date()
            date.setDate(date.getDate() + 1)
            date.setHours(23, 59, 0, 0)
        }
        selectedDate = date
        displayDate = new Date(date.getFullYear(), date.getMonth(), 1)
        timeText = Vikunja.pad2(date.getHours()) + ":" + Vikunja.pad2(date.getMinutes())
        validationError = ""
    }

    function displayValue() {
        var parsed = Vikunja.parseDueInput(value)
        if (!parsed.ok)
            return value || "Invalid due date"
        if (parsed.value === Vikunja.ZERO_DATE)
            return "No due date"
        var date = new Date(parsed.value)
        return Qt.formatDate(date, "ddd, d MMM yyyy") + " · " + Qt.formatTime(date, "HH:mm")
    }

    function parseTime() {
        var match = String(timeText || "").trim().match(/^(\d{1,2}):(\d{2})$/)
        if (!match)
            return -1
        var hours = parseInt(match[1])
        var minutes = parseInt(match[2])
        if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59)
            return -1
        return hours * 60 + minutes
    }

    function applySelection() {
        var minutes = parseTime()
        if (minutes < 0) {
            validationError = "Use a 24-hour time such as 09:00 or 23:59"
            return
        }
        var date = new Date(
            selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate(),
            Math.floor(minutes / 60), minutes % 60, 0, 0)
        valueEdited(Vikunja.dueInputFromDate(date))
        popup.close()
    }

    function applyPreset(kind) {
        if (kind === "clear")
            valueEdited("")
        else
            valueEdited(Vikunja.duePresetInput(kind, new Date(), value))
        popup.close()
    }

    function updateDirection() {
        var hostWindow = root.Window.window
        var windowHeight = hostWindow ? hostWindow.height : 0
        if (windowHeight <= 0) {
            openUpwards = false
            return
        }
        var topInWindow = root.mapToItem(null, 0, 0).y
        var spaceBelow = windowHeight - (topInWindow + root.height)
        openUpwards = spaceBelow < popup.height + Theme.spacingXS && topInWindow > spaceBelow
    }

    function popupX() {
        var hostWindow = root.Window.window
        var windowWidth = hostWindow ? hostWindow.width : 0
        if (windowWidth <= 0)
            return 0
        var leftInWindow = root.mapToItem(null, 0, 0).x
        if (leftInWindow + popup.width > windowWidth - Theme.spacingS)
            return windowWidth - Theme.spacingS - leftInWindow - popup.width
        if (leftInWindow < Theme.spacingS)
            return Theme.spacingS - leftInWindow
        return 0
    }

    onValueChanged: {
        if (!popup.visible)
            syncFromValue()
    }
    Component.onCompleted: syncFromValue()

    Rectangle {
        id: field

        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.width: 1
        border.color: popup.visible ? Theme.primary : Theme.outlineLight

        Column {
            anchors.left: parent.left
            anchors.right: fieldChevron.left
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            StyledText {
                width: parent.width
                text: root.labelText
                font.pixelSize: Theme.fontSizeSmall
                color: popup.visible ? Theme.primary : Theme.surfaceVariantText
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.displayValue()
                font.pixelSize: Theme.fontSizeMedium
                color: root.value === "" ? Theme.surfaceVariantText : Theme.surfaceText
                elide: Text.ElideRight
            }
        }

        DankIcon {
            id: fieldChevron
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: popup.visible ? "expand_less" : "calendar_month"
            size: Theme.iconSize - 5
            color: popup.visible ? Theme.primary : Theme.surfaceVariantText
        }

        StateLayer {
            stateColor: Theme.primary
            cornerRadius: parent.radius
            onClicked: popup.visible ? popup.close() : popup.open()
        }
    }

    Popup {
        id: popup

        readonly property int gridYear: root.displayDate.getFullYear()
        readonly property int gridMonth: root.displayDate.getMonth()
        readonly property int leadingDays: {
            var offset = new Date(gridYear, gridMonth, 1).getDay() - root.firstDayOfWeek
            return offset < 0 ? offset + 7 : offset
        }

        function cellDate(index) {
            return new Date(gridYear, gridMonth, 1 + index - leadingDays)
        }

        function sameDay(left, right) {
            return left.getFullYear() === right.getFullYear()
                && left.getMonth() === right.getMonth()
                && left.getDate() === right.getDate()
        }

        x: root.popupX()
        y: root.openUpwards ? -(height + Theme.spacingXS) : (field.height + Theme.spacingXS)
        width: 322
        height: pickerColumn.implicitHeight + padding * 2
        padding: Theme.spacingS
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        onAboutToShow: {
            root.syncFromValue()
            root.updateDirection()
        }

        background: Rectangle {
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius
            border.width: 1
            border.color: Theme.outlineMedium
        }

        contentItem: Column {
            id: pickerColumn

            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: "Set due date"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: [
                        { key: "today", label: "Today" },
                        { key: "tomorrow", label: "Tomorrow" },
                        { key: "weekend", label: "This weekend" },
                        { key: "nextweek", label: "Next week" },
                        { key: "clear", label: "No date" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: presetLabel.implicitWidth + Theme.spacingM * 2
                        height: 28
                        radius: 14
                        color: presetArea.containsMouse
                            ? Theme.withAlpha(Theme.primary, 0.2)
                            : Theme.surfaceContainerHighest

                        StyledText {
                            id: presetLabel
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            font.pixelSize: Theme.fontSizeSmall
                            color: parent.modelData.key === "clear"
                                ? Theme.surfaceVariantText : Theme.surfaceText
                        }

                        MouseArea {
                            id: presetArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyPreset(parent.modelData.key)
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outlineMedium
            }

            Item {
                width: parent.width
                height: 32

                DankActionButton {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "chevron_left"
                    iconColor: Theme.surfaceVariantText
                    onClicked: root.displayDate = new Date(popup.gridYear, popup.gridMonth - 1, 1)
                }

                StyledText {
                    anchors.centerIn: parent
                    text: Qt.formatDate(root.displayDate, "MMMM yyyy")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                }

                DankActionButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "chevron_right"
                    iconColor: Theme.surfaceVariantText
                    onClicked: root.displayDate = new Date(popup.gridYear, popup.gridMonth + 1, 1)
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: 7

                    delegate: Item {
                        required property int index
                        width: root.cellSize
                        height: 22

                        StyledText {
                            anchors.centerIn: parent
                            text: Qt.locale().dayName(
                                (parent.index + root.firstDayOfWeek) % 7, Locale.ShortFormat)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }
            }

            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 7

                Repeater {
                    model: 42

                    delegate: Rectangle {
                        id: dayCell

                        required property int index
                        readonly property date cellDay: popup.cellDate(index)
                        readonly property bool inMonth: cellDay.getMonth() === popup.gridMonth
                        readonly property bool selected: popup.sameDay(cellDay, root.selectedDate)
                        readonly property bool isToday: popup.sameDay(cellDay, new Date())

                        width: root.cellSize
                        height: root.cellSize - 4
                        radius: height / 2
                        color: selected ? Theme.primary : "transparent"
                        border.width: isToday && !selected ? 1 : 0
                        border.color: Theme.primary

                        StyledText {
                            anchors.centerIn: parent
                            text: dayCell.cellDay.getDate()
                            font.pixelSize: Theme.fontSizeSmall
                            color: dayCell.selected ? Theme.primaryText
                                : dayCell.inMonth ? Theme.surfaceText : Theme.surfaceVariantText
                        }

                        StateLayer {
                            stateColor: Theme.primary
                            cornerRadius: parent.radius
                            onClicked: {
                                root.selectedDate = dayCell.cellDay
                                root.validationError = ""
                            }
                        }
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingXS

                DankTextField {
                    width: 112
                    labelText: "Time"
                    placeholderText: "23:59"
                    text: root.timeText
                    onTextChanged: {
                        root.timeText = text
                        root.validationError = ""
                    }
                }

                Repeater {
                    model: ["09:00", "17:00", "23:59"]

                    delegate: Rectangle {
                        required property string modelData
                        width: timeLabel.implicitWidth + Theme.spacingM * 2
                        height: 32
                        radius: 16
                        color: root.timeText === modelData
                            ? Theme.withAlpha(Theme.primary, 0.24)
                            : timeArea.containsMouse
                                ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                        StyledText {
                            id: timeLabel
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.timeText === parent.modelData
                                ? Theme.primary : Theme.surfaceText
                        }

                        MouseArea {
                            id: timeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.timeText = parent.modelData
                                root.validationError = ""
                            }
                        }
                    }
                }
            }

            StyledText {
                width: parent.width
                visible: root.validationError !== ""
                text: root.validationError
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                wrapMode: Text.WordWrap
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                Item {
                    width: Math.max(0, parent.width - applyButton.width - Theme.spacingS)
                    height: 1
                }

                DankButton {
                    id: applyButton
                    text: "Apply"
                    iconName: "check"
                    buttonHeight: 32
                    backgroundColor: Theme.primary
                    textColor: Theme.primaryText
                    onClicked: root.applySelection()
                }
            }
        }
    }
}
