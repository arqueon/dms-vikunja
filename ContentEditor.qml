import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property alias text: contentArea.text
    property string labelText: "Content"
    property string placeholderText: "Add notes, context, checklists, or full web links"

    signal textEdited

    implicitHeight: 148
    radius: Theme.cornerRadius
    color: Theme.surfaceContainer
    border.width: contentArea.activeFocus ? 2 : 1
    border.color: contentArea.activeFocus ? Theme.primary : Theme.outlineMedium

    StyledText {
        id: fieldLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        anchors.topMargin: Theme.spacingXS
        text: root.labelText
        font.pixelSize: Theme.fontSizeSmall
        color: contentArea.activeFocus ? Theme.primary : Theme.surfaceVariantText
        elide: Text.ElideRight
    }

    ScrollView {
        id: contentScroll
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: fieldLabel.bottom
        anchors.bottom: fieldHelp.top
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        clip: true

        TextArea {
            id: contentArea
            width: contentScroll.availableWidth
            padding: Theme.spacingS
            placeholderText: root.placeholderText
            placeholderTextColor: Theme.outlineButton
            color: Theme.surfaceText
            selectionColor: Theme.primaryContainer
            selectedTextColor: Theme.primary
            font.pixelSize: Theme.fontSizeMedium
            font.family: Theme.fontFamily
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            background: null
            onTextChanged: root.textEdited()
        }
    }

    StyledText {
        id: fieldHelp
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        anchors.bottomMargin: Theme.spacingXS
        text: "Full http(s) links become clickable when saved"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        elide: Text.ElideRight
    }
}
