import QtQuick
import Quickshell
import Quickshell.Services.Pam

Scope {
    id: root

    signal unlocked()

    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool unlocking: false      // success: surfaces play their exit animation
    property int attempts: 0

    onCurrentTextChanged: if (currentText !== "") showFailure = false

    function reset() {
        currentText = "";
        unlockInProgress = false;
        showFailure = false;
        unlocking = false;
        attempts = 0;
    }

    function tryUnlock() {
        if (currentText === "" || pam.active || unlocking) return;
        unlockInProgress = true;
        pam.start();
    }

    PamContext {
        id: pam
        configDirectory: "pam"
        config: "password.conf"

        onPamMessage: {
            if (this.responseRequired) this.respond(root.currentText);
        }

        onCompleted: result => {
            root.unlockInProgress = false;
            if (result === PamResult.Success) {
                root.unlocking = true;
                finish.start();
            } else {
                root.attempts++;
                root.currentText = "";
                root.showFailure = true;
            }
        }
    }

    // Let the exit animation play before the compositor drops the lock surface
    Timer {
        id: finish
        interval: 450
        onTriggered: root.unlocked()
    }
}
