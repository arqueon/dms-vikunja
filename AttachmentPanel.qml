import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property var attachments: []
    property bool busy: false

    signal uploadRequested(var fileUrls)

    implicitHeight: attachmentColumn.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainer
    border.width: 1
    border.color: Theme.outlineMedium

    function fileData(attachment) {
        return attachment && attachment.file ? attachment.file : ({})
    }

    function formatSize(value) {
        var bytes = Number(value) || 0
        if (bytes < 1024)
            return bytes + " B"
        if (bytes < 1024 * 1024)
            return Math.round(bytes / 1024) + " KB"
        if (bytes < 1024 * 1024 * 1024)
            return (bytes / (1024 * 1024)).toFixed(1) + " MB"
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB"
    }

    Column {
        id: attachmentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                text: "Attachments"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            NumericText {
                visible: root.attachments.length > 0
                text: String(root.attachments.length)
                reserveText: "99+"
                width: reservedWidth
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Bold
                color: Theme.primary
                horizontalAlignment: Text.AlignHCenter
            }
        }

        StyledText {
            visible: root.attachments.length === 0
            width: parent.width
            text: "No files attached"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        Repeater {
            model: root.attachments

            delegate: Item {
                required property var modelData
                readonly property var metadata: root.fileData(modelData)
                width: attachmentColumn.width
                height: 38

                DankIcon {
                    id: attachmentIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: "attach_file"
                    size: 18
                    color: Theme.primary
                }

                Column {
                    anchors.left: attachmentIcon.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    StyledText {
                        width: parent.width
                        text: String(parent.parent.metadata.name || "Attachment")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        elide: Text.ElideMiddle
                    }

                    StyledText {
                        width: parent.width
                        text: {
                            var metadata = parent.parent.metadata
                            var parts = []
                            if (Number(metadata.size) >= 0)
                                parts.push(root.formatSize(metadata.size))
                            if (String(metadata.mime || ""))
                                parts.push(String(metadata.mime))
                            return parts.join(" · ")
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Row {
            spacing: Theme.spacingS

            DankButton {
                text: "Add files"
                iconName: "upload_file"
                buttonHeight: 30
                enabled: !root.busy
                onClicked: attachmentDialog.open()
            }

            BusyIndicator {
                visible: root.busy
                running: visible
                width: 24
                height: 24
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.busy
                text: "Uploading or updating…"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    FileDialog {
        id: attachmentDialog
        title: "Attach files to task"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["All files (*)"]
        onAccepted: {
            var files = []
            for (var i = 0; i < selectedFiles.length; i++)
                files.push(String(selectedFiles[i]))
            if (files.length > 0)
                root.uploadRequested(files)
        }
    }
}
