import QtQuick

// Hyprlock-style input: 250x50, rounded 10, 3px outline, centered dots.
Item {
    id: root
    required property var ctx

    property real shakeX: 0
    readonly property bool typing: ctx.currentText.length > 0

    width: 250
    height: 50
    transform: Translate { x: root.shakeX }

    function focusInput() { input.forceActiveFocus(); }

    Rectangle {
        id: box
        anchors.fill: parent
        radius: 10
        color: root.ctx.unlockInProgress ? Qt.alpha(Theme.surface, 0.85) : Qt.alpha(Theme.border, 0.65)
        border.width: 3
        border.color: root.ctx.showFailure ? Theme.danger
                    : root.ctx.unlockInProgress ? Theme.accent1
                    : root.typing ? Theme.accent2
                    : Qt.alpha(Theme.muted, 0.0)

        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }

        SequentialAnimation on opacity {
            running: root.ctx.unlockInProgress
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.6; duration: 350; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 350; easing.type: Easing.InOutSine }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !root.typing
        text: root.ctx.showFailure ? "Oops wrong !!(" + root.ctx.attempts + ")"
            : root.ctx.unlockInProgress ? "Checking..."
            : "What is it"
        font.family: Theme.font
        font.pixelSize: 15
        font.italic: root.ctx.showFailure
        color: root.ctx.showFailure ? Theme.danger : Qt.alpha(Theme.accent2, 0.75)
    }

    Row {
        anchors.centerIn: parent
        spacing: 3.6
        visible: root.typing
        Repeater {
            model: Math.min(root.ctx.currentText.length, 14)
            delegate: Rectangle {
                width: 12; height: 12; radius: 6
                color: root.ctx.unlockInProgress ? Theme.accent2 : Theme.accent1
                scale: 0
                Component.onCompleted: scale = 1
                Behavior on scale {
                    SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.01 }
                }
            }
        }
    }

    // Keypress feedback: tiny pulse
    SequentialAnimation {
        id: pulse
        NumberAnimation { target: root; property: "scale"; to: 1.04; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
    }

    // Wrong password: shake
    SequentialAnimation {
        id: shake
        NumberAnimation { target: root; property: "shakeX"; to: -14; duration: 50 }
        NumberAnimation { target: root; property: "shakeX"; to: 14;  duration: 80 }
        NumberAnimation { target: root; property: "shakeX"; to: -9;  duration: 70 }
        NumberAnimation { target: root; property: "shakeX"; to: 5;   duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: 0;   duration: 60; easing.type: Easing.OutQuad }
    }

    Connections {
        target: root.ctx
        function onShowFailureChanged() { if (root.ctx.showFailure) shake.restart(); }
        function onCurrentTextChanged() {
            if (input.text !== root.ctx.currentText) input.text = root.ctx.currentText;
            if (root.ctx.currentText.length > 0) pulse.restart();
        }
    }

    // Invisible text input that owns keyboard focus; text is mirrored into the shared context
    TextInput {
        id: input
        width: 1; height: 1
        opacity: 0
        focus: true
        echoMode: TextInput.Password
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        onTextChanged: if (root.ctx.currentText !== text) root.ctx.currentText = text
        onAccepted: root.ctx.tryUnlock()
        Keys.onEscapePressed: text = ""
        Component.onCompleted: forceActiveFocus()
    }
}
