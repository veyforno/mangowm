import QtQuick

// Auto-resizing lyrics box. Springs to fit the active lyric lines; shows
// "Nothing Here..." unless MPD is actually playing.
Rectangle {
    id: panel

    readonly property bool active: Media.playerState === "play"
    readonly property int padX: 30
    readonly property int padY: 22
    readonly property int maxTextW: 480
    readonly property int minTextW: 160

    readonly property string headerStr: active
        ? "♪  " + (Media.artist !== "" ? Media.artist + " — " : "") + Media.title : ""
    readonly property string prevStr: active && Media.hasLyrics ? Media.prevLine : ""
    readonly property string curStr: !active ? "Nothing Here..."
        : Media.hasLyrics ? (Media.line !== "" ? Media.line : "♪")
        : "No lyrics found"
    readonly property string nextStr: active && Media.hasLyrics ? Media.nextLine : ""

    TextMetrics { id: mHead; text: panel.headerStr; font.family: Theme.font; font.pixelSize: 12 }
    TextMetrics { id: mPrev; text: panel.prevStr;   font.family: Theme.font; font.pixelSize: 13 }
    TextMetrics { id: mCur;  text: panel.curStr;    font.family: Theme.font; font.pixelSize: 18; font.bold: true }
    TextMetrics { id: mNext; text: panel.nextStr;   font.family: Theme.font; font.pixelSize: 13 }

    // Width follows the longest line (capped; longer lines wrap and grow the height)
    readonly property real contentW: Math.min(maxTextW,
        Math.max(minTextW, mHead.width, mPrev.width, mCur.width, mNext.width) + 4)

    width: contentW + padX * 2
    height: col.implicitHeight + padY * 2
    radius: 20
    clip: true
    color: Qt.alpha(Theme.border, 0.65)
    border.width: 2
    border.color: active ? Qt.alpha(Theme.muted, 0.9) : Qt.alpha(Theme.muted, 0.0)

    Behavior on border.color { ColorAnimation { duration: 300 } }
    Behavior on width  { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.5 } }
    Behavior on height { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.5 } }

    Column {
        id: col
        anchors.centerIn: parent
        width: panel.contentW
        spacing: 8

        Text {
            width: parent.width
            visible: text !== ""
            text: panel.headerStr
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.accent1
            font.family: Theme.font; font.pixelSize: 12
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: panel.prevStr
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Qt.alpha(Theme.accent1, 0.4)
            font.family: Theme.font; font.pixelSize: 13
        }
        Text {
            id: cur
            width: parent.width
            text: panel.curStr
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: panel.active ? Theme.accent2 : Qt.alpha(Theme.accent1, 0.6)
            font.family: Theme.font
            font.pixelSize: panel.active ? 18 : 16
            font.bold: panel.active
            transform: Translate { id: curShift; y: 0 }
            Behavior on color { ColorAnimation { duration: 250 } }
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: panel.nextStr
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Qt.alpha(Theme.accent1, 0.4)
            font.family: Theme.font; font.pixelSize: 13
        }
    }

    // Crossfade + small slide whenever the current line changes
    ParallelAnimation {
        id: lineIn
        NumberAnimation { target: cur; property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: curShift; property: "y"; from: 8; to: 0; duration: 280; easing.type: Easing.OutCubic }
    }
    Connections {
        target: Media
        function onLineChanged() { lineIn.restart(); }
        function onPlayerStateChanged() { lineIn.restart(); }
    }
}
