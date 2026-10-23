import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Scope {
    id: root

    property bool hasScreenshot: false
    property string screenshotPath: ""

    property bool recording: false
    property bool hasRecording: false
    property string recordingPath: ""
    property int recordSeconds: 0

    property string pendingMode: ""
    property string pendingGeometry: ""

    readonly property string home: Quickshell.env("HOME")

    function stamp() {
        return Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
    }

    // mode: "shot" | "record"
    function startCapture(mode) {
        if (slurp.running || shotProc.running || startDelay.running)
            return;
        if (mode === "record" && root.recording)
            return;

        root.pendingMode = mode;
        root.pendingGeometry = "";
        startDelay.restart();
    }

    Timer {
        id: startDelay
        interval: 250
        repeat: false
        onTriggered: slurp.running = true
    }

    function runScreenshot(geometry) {
        var dir = root.home + "/Pictures/Screenshots";
        var path = dir + "/screenshot-" + root.stamp() + ".png";

        shotProc.targetPath = path;
        shotProc.command = ["sh", "-c", "mkdir -p \"$1\" && grim -g \"$2\" \"$3\"", "sh", dir, geometry, path];
        shotProc.running = true;
    }

    function runRecording(geometry) {
        var dir = root.home + "/Videos/Recordings";
        var path = dir + "/recording-" + root.stamp() + ".mp4";

        root.recordingPath = path;
        root.recordSeconds = 0;
        root.hasRecording = false;
        root.recording = true;

        recordProc.command = ["sh", "-c", "mkdir -p \"$1\" && exec wf-recorder -g \"$2\" -f \"$3\"", "sh", dir, geometry, path];
        recordProc.running = true;
    }

    function stopRecording() {
        if (root.recording)
            stopProc.running = true;
    }

    function copyScreenshot() {
        if (root.screenshotPath !== "")
            Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", root.screenshotPath]);
    }

    function openFile(path) {
        if (path !== "")
            Hyprland.dispatch("exec xdg-open '" + path + "'");
    }

    function deleteScreenshot() {
        if (root.screenshotPath !== "")
            Quickshell.execDetached(["rm", "-f", root.screenshotPath]);
        root.dismissScreenshot();
    }

    function dismissScreenshot() {
        root.hasScreenshot = false;
        root.screenshotPath = "";
    }

    function deleteRecording() {
        if (root.recordingPath !== "")
            Quickshell.execDetached(["rm", "-f", root.recordingPath]);
        root.dismissRecording();
    }

    function dismissRecording() {
        root.hasRecording = false;
        root.recordingPath = "";
    }

    // Region picker, shared by screenshot and recording
    Process {
        id: slurp
        command: ["sh", "-c", "exec slurp -b '#00000066' -c '#ffffffff' -s '#ffffff22' -w 2 </dev/null"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                root.pendingGeometry = data.trim();
            }
        }

        onExited: (code, status) => {
            if (code !== 0 || root.pendingGeometry === "")
                return;

            if (root.pendingMode === "shot")
                root.runScreenshot(root.pendingGeometry);
            else
                root.runRecording(root.pendingGeometry);
        }
    }

    Process {
        id: shotProc
        property string targetPath: ""
        command: []
        running: false

        onExited: (code, status) => {
            if (code === 0) {
                root.screenshotPath = shotProc.targetPath;
                root.hasScreenshot = true;
            }
        }
    }

    Process {
        id: recordProc
        command: []
        running: false

        onExited: (code, status) => {
            root.recording = false;
            // If wf-recorder failed immediately, don't show a chip for a file that doesn't exist
            root.hasRecording = root.recordSeconds > 0;
        }
    }

    // wf-recorder only finalizes the file cleanly on SIGINT
    Process {
        id: stopProc
        command: ["pkill", "-INT", "-x", "wf-recorder"]
        running: false
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.recordSeconds += 1
    }
}
