import QtQuick
import QtQuick.Controls
import QtQuick.Window
import qs.Common
import qs.Widgets
import "./JS/vikunja.js" as Vikunja

Item {
    id: root

    property var options: []
    property int selectedId: 0
    property string labelText: "Project"
    property string placeholderText: "Choose a project"
    property string query: ""
    property bool openUpwards: false

    signal projectSelected(int projectId)

    readonly property var currentOption: {
        for (var i = 0; i < options.length; i++) {
            if (parseInt(options[i].id) === selectedId)
                return options[i]
        }
        return null
    }
    readonly property var filteredOptions: Vikunja.filterProjectOptions(options, query)

    implicitHeight: 64
    height: implicitHeight

    function updateDirection() {
        var hostWindow = root.Window.window
        var windowHeight = hostWindow ? hostWindow.height : 0
        if (windowHeight <= 0) {
            openUpwards = false
            return
        }
        var topInWindow = root.mapToItem(null, 0, 0).y
        var spaceBelow = windowHeight - (topInWindow + root.height)
        openUpwards = spaceBelow < pickerPopup.height + Theme.spacingXS
            && topInWindow > spaceBelow
    }

    function availablePopupWidth() {
        var hostWindow = root.Window.window
        var windowWidth = hostWindow ? hostWindow.width : 0
        if (windowWidth <= 0)
            return root.width
        return Math.min(root.width, windowWidth - Theme.spacingM * 2)
    }

    function popupX() {
        var hostWindow = root.Window.window
        var windowWidth = hostWindow ? hostWindow.width : 0
        if (windowWidth <= 0)
            return 0
        var leftInWindow = root.mapToItem(null, 0, 0).x
        if (leftInWindow + pickerPopup.width > windowWidth - Theme.spacingM)
            return windowWidth - Theme.spacingM - leftInWindow - pickerPopup.width
        if (leftInWindow < Theme.spacingM)
            return Theme.spacingM - leftInWindow
        return 0
    }

    function selectedIndex() {
        for (var i = 0; i < filteredOptions.length; i++) {
            if (parseInt(filteredOptions[i].id) === selectedId)
                return i
        }
        return -1
    }

    function choose(option) {
        if (!option)
            return
        projectSelected(parseInt(option.id))
        pickerPopup.close()
    }

    Rectangle {
        id: field

        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.width: 1
        border.color: pickerPopup.visible ? Theme.primary : Theme.outlineLight

        DankIcon {
            id: projectIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: root.currentOption && root.currentOption.depth > 0
                ? "account_tree" : "folder"
            size: Theme.iconSize - 4
            color: pickerPopup.visible ? Theme.primary : Theme.surfaceVariantText
        }

        Column {
            anchors.left: projectIcon.right
            anchors.right: fieldChevron.left
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            StyledText {
                width: parent.width
                text: root.labelText
                font.pixelSize: Theme.fontSizeSmall
                color: pickerPopup.visible ? Theme.primary : Theme.surfaceVariantText
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.currentOption
                    ? String(root.currentOption.title || "Untitled") : root.placeholderText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: root.currentOption ? Font.Medium : Font.Normal
                color: root.currentOption ? Theme.surfaceText : Theme.surfaceVariantText
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                visible: root.currentOption && String(root.currentOption.parentPath || "") !== ""
                text: root.currentOption ? String(root.currentOption.parentPath || "") : ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideMiddle
            }
        }

        DankIcon {
            id: fieldChevron
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: pickerPopup.visible ? "expand_less" : "expand_more"
            size: Theme.iconSize - 4
            color: pickerPopup.visible ? Theme.primary : Theme.surfaceVariantText
        }

        StateLayer {
            stateColor: Theme.primary
            cornerRadius: parent.radius
            onClicked: pickerPopup.visible ? pickerPopup.close() : pickerPopup.open()
        }
    }

    Popup {
        id: pickerPopup

        property int keyboardIndex: -1

        x: root.popupX()
        y: root.openUpwards ? -(height + Theme.spacingXS) : (field.height + Theme.spacingXS)
        width: root.availablePopupWidth()
        height: Math.min(430, popupColumn.implicitHeight + padding * 2)
        padding: Theme.spacingS
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        onAboutToShow: {
            root.query = ""
            keyboardIndex = root.selectedIndex()
            root.updateDirection()
            Qt.callLater(function() {
                searchField.forceActiveFocus()
                if (keyboardIndex >= 0)
                    projectList.positionViewAtIndex(keyboardIndex, ListView.Center)
            })
        }

        background: Rectangle {
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius
            border.width: 1
            border.color: Theme.primary
        }

        contentItem: Column {
            id: popupColumn

            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: "Choose project"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            DankTextField {
                id: searchField
                width: parent.width
                placeholderText: "Search project or parent path"
                leftIconName: "search"
                text: root.query
                onTextChanged: {
                    root.query = text
                    pickerPopup.keyboardIndex = root.filteredOptions.length > 0 ? 0 : -1
                }
                Keys.onDownPressed: {
                    if (root.filteredOptions.length === 0)
                        return
                    pickerPopup.keyboardIndex = Math.min(
                        root.filteredOptions.length - 1, pickerPopup.keyboardIndex + 1)
                    projectList.positionViewAtIndex(pickerPopup.keyboardIndex, ListView.Contain)
                }
                Keys.onUpPressed: {
                    if (root.filteredOptions.length === 0)
                        return
                    pickerPopup.keyboardIndex = Math.max(0, pickerPopup.keyboardIndex - 1)
                    projectList.positionViewAtIndex(pickerPopup.keyboardIndex, ListView.Contain)
                }
                Keys.onReturnPressed: {
                    if (pickerPopup.keyboardIndex >= 0)
                        root.choose(root.filteredOptions[pickerPopup.keyboardIndex])
                }
                Keys.onEnterPressed: {
                    if (pickerPopup.keyboardIndex >= 0)
                        root.choose(root.filteredOptions[pickerPopup.keyboardIndex])
                }
            }

            Item {
                width: parent.width
                implicitHeight: Math.max(52, Math.min(root.filteredOptions.length, 6) * 54)
                height: implicitHeight

                ListView {
                    id: projectList
                    anchors.fill: parent
                    clip: true
                    spacing: Theme.spacingXS
                    model: root.filteredOptions

                    delegate: Rectangle {
                        id: optionRow

                        required property var modelData
                        required property int index
                        readonly property bool selected:
                            parseInt(modelData.id) === root.selectedId

                        width: projectList.width
                        height: 50
                        radius: Theme.cornerRadius
                        color: pickerPopup.keyboardIndex === index
                            ? Theme.withAlpha(Theme.primary, 0.18)
                            : optionArea.containsMouse
                                ? Theme.surfaceContainerHighest : "transparent"
                        border.width: selected ? 1 : 0
                        border.color: Theme.primary

                        DankIcon {
                            id: optionIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                                + Math.min(parseInt(modelData.depth) || 0, 3) * Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            name: (parseInt(modelData.depth) || 0) > 0
                                ? "subdirectory_arrow_right" : "folder"
                            size: Theme.iconSize - 5
                            color: optionRow.selected ? Theme.primary : Theme.surfaceVariantText
                        }

                        Column {
                            anchors.left: optionIcon.right
                            anchors.right: selectedIcon.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            StyledText {
                                width: parent.width
                                text: String(optionRow.modelData.title || "Untitled")
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: optionRow.selected ? Font.Medium : Font.Normal
                                color: optionRow.selected ? Theme.primary : Theme.surfaceText
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: String(optionRow.modelData.parentPath || "Top-level project")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideMiddle
                            }
                        }

                        DankIcon {
                            id: selectedIcon
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            visible: optionRow.selected
                            name: "check"
                            size: Theme.iconSize - 5
                            color: Theme.primary
                        }

                        MouseArea {
                            id: optionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.choose(parent.modelData)
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.filteredOptions.length === 0
                        text: "No projects match this search"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }
}
