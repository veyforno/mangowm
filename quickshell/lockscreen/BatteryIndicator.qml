import QtQuick
import Quickshell.Services.UPower

// Drawn battery icon + percent. Hides itself on machines without a battery.
Row {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property real raw: dev ? dev.percentage : 0
    readonly property int pct: Math.round(raw <= 1 ? raw * 100 : raw)   // handles 0-1 or 0-100
    readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging
                                          || dev.state === UPowerDeviceState.FullyCharged)
    readonly property bool low: pct <= 20 && !charging

    visible: dev && dev.isPresent
    spacing: 10

    // battery body
    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: 36; height: 16

        Rectangle {
            id: body
            width: 32; height: 16
            radius: 4
            color: Qt.alpha(Theme.border, 0.65)
            border.width: 2
            border.color: root.low ? Theme.danger : Theme.accent1

            Rectangle {
                x: 3; y: 3
                height: parent.height - 6
                width: Math.max(0, (parent.width - 6) * Math.min(root.pct, 100) / 100)
                radius: 2
                color: root.low ? Theme.danger : root.charging ? Theme.accent1 : Theme.accent2
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 250 } }
            }
        }
        // terminal nub
        Rectangle {
            x: 32; anchors.verticalCenter: body.verticalCenter
            width: 3; height: 7; radius: 1.5
            color: root.low ? Theme.danger : Theme.accent1
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: (root.charging ? "\uf0e7 " : "") + root.pct + "%"
        color: root.low ? Theme.danger : Theme.accent1
        font.family: Theme.font
        font.pixelSize: 15
        font.bold: true
    }
}
