pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // Palette
    readonly property color bg:      "#171723"
    readonly property color accent1: "#B9D4E3"
    readonly property color accent2: "#A6CAE4"
    readonly property color surface: "#1e1e1e"
    readonly property color muted:   "#5b4950"
    readonly property color border:  "#222233"
    readonly property color danger:  "#ff5c6c"

    readonly property string font: "JetBrainsMono Nerd Font"

    // Same assets as your hyprlock.conf (edit if they move)
    readonly property string wallpaper: "file://" + "/home/nanoarch/Pictures/Wallpapers/wallhaven1.png" // + Quickshell.env("HOME") + "/Pictures/Wallpapers/wallhaven1.png"
    readonly property string avatar:    "file://" + "/home/nanoarch/Pictures/avatar/mybg.jpg" // + Quickshell.env("HOME") + "/Pictures/avatar/mybg.jpg"
}
