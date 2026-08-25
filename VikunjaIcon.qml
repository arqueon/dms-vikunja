// Official monochrome Vikunja badge, tinted to the active DMS theme.

import QtQuick
import QtQuick.Effects
import qs.Common

Item {
    id: root

    property int size: 20
    property real opticalScale: 0.90
    property color iconColor: Theme.surfaceText
    property real iconOpacity: 1.0

    width: size
    height: size

    Image {
        width: Math.round(root.size * root.opticalScale)
        height: width
        anchors.centerIn: parent
        source: Qt.resolvedUrl("Images/vikunja-monochrome.svg")
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        antialiasing: true
        cache: false
        opacity: root.iconOpacity
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            saturation: 0
            colorization: 1
            colorizationColor: root.iconColor
        }
    }
}
