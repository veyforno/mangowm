import QtQuick

// Slider sederhana buatan sendiri (horizontal / vertikal), warnanya ikut tema bar
Item {
    id: s
    property real from: 0
    property real to: 1
    property real value: 0
    property real origin: 0            // titik awal isian (0 = dari ujung, 0.5 = dari tengah, untuk EQ)
    property bool vertical: false
    property color trackColor: "#222233"
    property color fillColor: "#A6CAE4"
    signal moved(real v)               // dipanggil saat user menggeser

    readonly property real ratio: to === from ? 0 : Math.max(0, Math.min(1, (value - from) / (to - from)))
    readonly property int  hs: 14      // ukuran handle

    // posisi titik tengah handle untuk rasio r (0..1)
    function pos(r) {
        return vertical ? hs / 2 + (1 - r) * (height - hs)
                        : hs / 2 + r * (width - hs)
    }

    // jalur (track)
    Rectangle {
        radius: 3
        color: s.trackColor
        width:  s.vertical ? 6 : s.width
        height: s.vertical ? s.height : 6
        x: s.vertical ? (s.width - 6) / 2 : 0
        y: s.vertical ? 0 : (s.height - 6) / 2
    }

    // isian (dari origin sampai posisi sekarang)
    Rectangle {
        radius: 3
        color: s.fillColor
        readonly property real a: s.pos(s.origin)
        readonly property real b: s.pos(s.ratio)
        width:  s.vertical ? 6 : Math.abs(b - a)
        height: s.vertical ? Math.abs(b - a) : 6
        x: s.vertical ? (s.width - 6) / 2 : Math.min(a, b)
        y: s.vertical ? Math.min(a, b) : (s.height - 6) / 2
    }

    // handle (bulatan yang digeser)
    Rectangle {
        width: s.hs; height: s.hs; radius: s.hs / 2
        color: s.fillColor
        x: s.vertical ? (s.width - s.hs) / 2 : s.pos(s.ratio) - s.hs / 2
        y: s.vertical ? s.pos(s.ratio) - s.hs / 2 : (s.height - s.hs) / 2
    }

    MouseArea {
        anchors.fill: parent
        function update(mouse) {
            let r = s.vertical ? 1 - (mouse.y - s.hs / 2) / (s.height - s.hs)
                               : (mouse.x - s.hs / 2) / (s.width - s.hs)
            r = Math.max(0, Math.min(1, r))
            s.moved(s.from + r * (s.to - s.from))
        }
        onPressed: mouse => update(mouse)
        onPositionChanged: mouse => { if (pressed) update(mouse) }
    }
}
