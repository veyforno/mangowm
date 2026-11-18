import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    LockContext {
        id: ctx
        onUnlocked: sessionLock.locked = false
    }

    WlSessionLock {
        id: sessionLock
        // LOCKSCREEN_NOW=1 qs -c lockscreen  -> lock immediately (handy for testing)
        locked: Quickshell.env("LOCKSCREEN_NOW") === "1"
        onLockedChanged: if (locked) ctx.reset()

        WlSessionLockSurface {
            color: Theme.bg
            LockSurface {
                anchors.fill: parent
                context: ctx
            }
        }
    }

    // Only poll MPD while the screen is actually locked
    Binding { target: Media; property: "enabled"; value: sessionLock.locked }

    // qs -c lockscreen ipc call lock lock
    IpcHandler {
        target: "lock"
        function lock(): void { sessionLock.locked = true; }
    }
}
