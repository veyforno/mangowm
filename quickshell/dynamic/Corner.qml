import QtQuick

// Sudut cekung kecil: bikin panel terlihat "tumbuh" dari bar (efek menyatu)
Canvas {
    property color fill: "#171723"
    property bool mirrored: false    // false = di kiri panel, true = di kanan panel
    width: 16
    height: 16

    onPaint: {
        const c = getContext("2d")
        c.reset()
        c.fillStyle = fill
        c.beginPath()
        if (!mirrored) {
            c.moveTo(0, 0); c.lineTo(width, 0); c.lineTo(width, height)
            c.arc(0, height, width, 0, -Math.PI / 2, true)
        } else {
            c.moveTo(width, 0); c.lineTo(0, 0); c.lineTo(0, height)
            c.arc(width, height, width, Math.PI, 3 * Math.PI / 2, false)
        }
        c.closePath()
        c.fill()
    }
}
