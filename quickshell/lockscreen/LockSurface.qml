import QtQuick
import QtQuick.Effects
import Quickshell

Rectangle {
    id: root
    required property var context
    color: Theme.bg

    readonly property string userName: {
        const u = Quickshell.env("USER") || "user";
        return u.charAt(0).toUpperCase() + u.slice(1);
    }
    readonly property string statusText:
        context.unlocking ? "Welcome back"
        : context.unlockInProgress ? "Checking..."
        : context.showFailure ? "Wrong password"
        : context.currentText.length > 0 ? "Press Enter to unlock"
        : "Locked"

    // ---- intro / exit animation state --------------------------------------
    property real inClock: 0
    property real inAvatar: 0
    property real inInput: 0
    property real inMedia: 0
    property real exit: context.unlocking ? 1 : 0
    Behavior on exit { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }

    ParallelAnimation {
        running: true
        NumberAnimation { target: root; property: "inClock"; to: 1; duration: 700; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 140 }
            NumberAnimation { target: root; property: "inAvatar"; to: 1; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 280 }
            NumberAnimation { target: root; property: "inInput"; to: 1; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 420 }
            NumberAnimation { target: root; property: "inMedia"; to: 1; duration: 700; easing.type: Easing.OutCubic }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // ---- background (blur + dim, like hyprlock's blur_passes/brightness) ----
    Image {
        id: wp
        anchors.fill: parent
        source: Theme.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wp
        visible: wp.status === Image.Ready
        blurEnabled: true
        blur: 0.55
        blurMax: 48
        brightness: -0.12
        contrast: -0.05
        saturation: 0.1
    }
    Rectangle { anchors.fill: parent; color: Theme.bg; opacity: 0.55 }

    MouseArea { anchors.fill: parent; onClicked: field.focusInput() }

    // ---- content ----------------------------------------------------------
    Item {
        id: content
        anchors.fill: parent
        opacity: 1 - root.exit
        scale: 1 + root.exit * 0.03

        // Left: lock core
        Item {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * 0.5

            Column {
                id: col
                anchors.centerIn: parent
                width: 420
                spacing: 14

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\uf023"
                    color: Theme.accent2
                    font.family: Theme.font; font.pixelSize: 28
                    opacity: root.inClock
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, "HH:mm:ss")
                    color: Theme.accent1
                    font.family: Theme.font; font.pixelSize: 64; font.bold: true
                    opacity: root.inClock
                    transform: Translate { y: (1 - root.inClock) * -28 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, "dddd, dd MM yyyy")
                    color: Theme.accent2
                    font.family: Theme.font; font.pixelSize: 22; font.bold: true
                    opacity: root.inClock
                    transform: Translate { y: (1 - root.inClock) * -20 }
                }

                Item { width: 1; height: 16 }

                // Avatar
                Item {
                    id: avatar
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property int size: Math.min(300, root.height * 0.27)
                    width: size; height: size
                    opacity: Math.min(1, root.inAvatar)
                    scale: (0.7 + 0.3 * root.inAvatar)

                    SequentialAnimation on scale {
                        running: root.context.unlockInProgress
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 1.03; duration: 450; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0;  duration: 450; easing.type: Easing.InOutSine }
                    }

                    Item {
                        id: avatarMask
                        anchors.fill: parent
                        layer.enabled: true
                        visible: false
                        Rectangle { anchors.fill: parent; radius: width / 2 }
                    }
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: Theme.surface
                        visible: avatarImg.status !== Image.Ready
                        Text {
                            anchors.centerIn: parent
                            text: root.userName.charAt(0)
                            color: Theme.accent1
                            font.family: Theme.font; font.pixelSize: avatar.size * 0.4; font.bold: true
                        }
                    }
                    Image {
                        id: avatarImg
                        anchors.fill: parent
                        source: Theme.avatar
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(avatar.size * 2, avatar.size * 2)
                        asynchronous: true
                        visible: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: avatarImg
                        maskEnabled: true
                        maskSource: avatarMask
                        visible: avatarImg.status === Image.Ready
                    }
                }

                // Name + dynamic status
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.userName
                    color: Theme.accent1
                    font.family: Theme.font; font.pixelSize: 20; font.bold: true
                    opacity: root.inAvatar > 1 ? 1 : root.inAvatar
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.statusText
                    color: root.context.showFailure ? Theme.danger : Qt.alpha(Theme.accent2, 0.8)
                    font.family: Theme.font; font.pixelSize: 13
                    opacity: root.inAvatar > 1 ? 1 : root.inAvatar
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                Item { width: 1; height: 10 }

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: field.width; height: field.height
                    opacity: Math.min(1, root.inInput)
                    transform: Translate { y: (1 - root.inInput) * 30 }
                    InputField { id: field; ctx: root.context }
                }

                Item { width: 1; height: 6 }

                BatteryIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: Math.min(1, root.inInput)
                    transform: Translate { y: (1 - root.inInput) * 30 }
                }
            }
        }

        // Right: media / lyrics
        Item {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: parent.width * 0.5

            MediaPanel {
                anchors.centerIn: parent
                opacity: root.inMedia
                transform: Translate { x: (1 - root.inMedia) * 40 }
            }
        }
    }
}
