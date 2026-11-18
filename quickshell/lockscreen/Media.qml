pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Streams JSON lines from scripts/nowplaying.py (MPD, which rmpc controls).
Singleton {
    id: root

    property bool enabled: false          // bound from shell.qml: only poll while locked
    property string playerState: "stop"   // play | pause | stop
    property string title: ""
    property string artist: ""
    property string album: ""
    property string prevLine: ""
    property string line: ""
    property string nextLine: ""
    property bool hasLyrics: false

    Process {
        id: proc
        running: root.enabled
        command: ["python3", Quickshell.shellPath("scripts/nowplaying.py")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const o = JSON.parse(data);
                    root.playerState = o.state;
                    root.title = o.title;
                    root.artist = o.artist;
                    root.album = o.album;
                    root.prevLine = o.prev;
                    root.line = o.line;
                    root.nextLine = o.next;
                    root.hasLyrics = o.hasLyrics;
                } catch (e) {}
            }
        }
        onExited: if (root.enabled) restart.start()
    }

    Timer {
        id: restart
        interval: 2000
        onTriggered: if (root.enabled) proc.running = true
    }
}
