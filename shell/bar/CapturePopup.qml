import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ciel.Ui

PopupWindow {
    id: root

    property var targetWindow
    property rect anchorRect
    property var capture
    property string kind: "shot" // "shot" | "record"
    property bool isOpen: false

    readonly property bool isRecordingNow: capture ? capture.recording : false

    readonly property var actions: {
        if (kind === "shot") {
            return [
                {key: "copy", icon: "copy", label: "Copy", danger: false},
                {key: "open", icon: "arrow-square-out", label: "Open", danger: false},
                {key: "delete", icon: "trash", label: "Delete", danger: true},
                {key: "dismiss", icon: "x", label: "Dismiss", danger: false}
            ];
        }
        if (isRecordingNow)
            return [{key: "stop", icon: "stop", label: "Stop", danger: true}];

        return [
            {key: "open", icon: "arrow-square-out", label: "Open", danger: false},
            {key: "delete", icon: "trash", label: "Delete", danger: true},
            {key: "dismiss", icon: "x", label: "Dismiss", danger: false}
        ];
    }

    readonly property string currentPath: !capture ? "" : (kind === "shot" ? capture.screenshotPath : capture.recordingPath)

    readonly property string title: kind === "shot" ? "Screenshot" : (isRecordingNow ? "Recording" : "Recording saved")

    function formatDuration(s) {
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    function runAction(key) {
        if (!capture)
            return;

        if (key === "copy") {
            capture.copyScreenshot();
        } else if (key === "open") {
            capture.openFile(root.currentPath);
        } else if (key === "delete") {
            if (kind === "shot")
                capture.deleteScreenshot();
            else
                capture.deleteRecording();
        } else if (key === "dismiss") {
            if (kind === "shot")
                capture.dismissScreenshot();
            else
                capture.dismissRecording();
        } else if (key === "stop") {
            capture.stopRecording();
        }

        // Stop keeps the popup open so it flips to the saved-state actions
        if (key !== "stop")
            root.isOpen = false;
    }

    // Close if the thing this popup is about disappears
    Connections {
        target: root.capture

        function onHasScreenshotChanged() {
            if (root.kind === "shot" && !root.capture.hasScreenshot)
                root.isOpen = false;
        }

        function onHasRecordingChanged() {
            if (root.kind === "record" && !root.capture.hasRecording && !root.capture.recording)
                root.isOpen = false;
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.isOpen
        onActivated: root.isOpen = false
    }

    readonly property real startY: -14
    readonly property real startXScale: 0.84
    readonly property real startYScale: 0.74

    readonly property real springY: 4.2
    readonly property real dampingY: 0.34
    readonly property real springX: 4.5
    readonly property real dampingX: 0.36
    readonly property real springPosY: 4.2
    readonly property real dampingPosY: 0.34

    readonly property int fadeInDuration: 95
    readonly property int closeDuration: 130

    function toggle() {
        isOpen = !isOpen;
    }

    onIsOpenChanged: {
        if (isOpen) {
            visible = true;
            closeAnim.stop();
            openAnim.restart();
        } else {
            openAnim.stop();

            if (visible)
                closeAnim.restart();
            else
                closeAnim.stop();
        }
    }

    anchor.window: targetWindow
    anchor.rect: anchorRect
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    implicitWidth: 320
    implicitHeight: popupContent.height + 50
    color: "transparent"

    grabFocus: false

    visible: root.isOpen || openAnim.running || closeAnim.running

    HyprlandFocusGrab {
        windows: [root]
        active: root.isOpen

        onCleared: {
            if (root.isOpen)
                root.isOpen = false;
        }
    }

    RectangularShadow {
        anchors.fill: popupContent
        radius: 20
        offset.y: 10
        blur: 38
        spread: -8
        color: "#00000080"
        opacity: popupContent.opacity
    }

    Item {
        id: popupContent
        property real radius: 20
        width: 270
        height: contentLayout.implicitHeight + 36
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        opacity: 0.0

        transform: Scale {
            id: scaleTransform
            origin.x: popupContent.width / 2
            origin.y: 0
            xScale: root.startXScale
            yScale: root.startYScale
        }

        CielSquircle {
            anchors.fill: parent
            radius: popupContent.radius
            color: Theme.surface
            borderColor: Theme.surfaceHover
            borderWidth: 1
        }

        ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                CielIcon {
                    id: headerIcon
                    icon: root.kind === "shot" ? "corners-out" : (root.isRecordingNow ? "record" : "video-camera")
                    size: Theme.SMALL
                    color: root.isRecordingNow ? "#ff5555" : Theme.textPrimary

                    SequentialAnimation on opacity {
                        running: root.isRecordingNow && root.isOpen
                        loops: Animation.Infinite

                        NumberAnimation {
                            to: 0.35
                            duration: 600
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            to: 1.0
                            duration: 600
                            easing.type: Easing.InOutQuad
                        }

                        onRunningChanged: {
                            if (!running)
                                headerIcon.opacity = 1.0;
                        }
                    }
                }

                Text {
                    text: root.title
                    color: Theme.textPrimary
                    font.pixelSize: 15
                    font.bold: true
                    renderType: Text.NativeRendering
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.isRecordingNow
                    text: root.capture ? root.formatDuration(root.capture.recordSeconds) : ""
                    color: Theme.textSecondary
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.surfaceHover
            }

            // Screenshot preview
            Item {
                visible: root.kind === "shot" && root.currentPath !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 130 : 0

                CielSquircle {
                    anchors.fill: parent
                    radius: 12
                    color: Theme.surfaceHover
                    borderWidth: 0
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: 4
                    source: root.kind === "shot" && root.currentPath !== "" ? "file://" + root.currentPath : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    smooth: true
                    sourceSize.width: 520
                }
            }

            // File name (recording states, and under the screenshot preview)
            Text {
                visible: root.currentPath !== ""
                Layout.fillWidth: true
                text: root.currentPath.split("/").pop()
                color: Theme.textSecondary
                font.pixelSize: 11
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }

            GridLayout {
                Layout.fillWidth: true
                columns: Math.max(1, root.actions.length)
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: root.actions

                    delegate: Item {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 74
                        implicitHeight: 74

                        CielSquircle {
                            id: tileFace
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 48
                            radius: 16
                            color: tileMouse.containsMouse ? Theme.surface : Theme.surfaceHover
                            borderWidth: 0
                        }

                        Text {
                            anchors.top: tileFace.bottom
                            anchors.topMargin: 4
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: modelData.label
                            color: Theme.textSecondary
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            renderType: Text.NativeRendering
                        }

                        CielIcon {
                            anchors.centerIn: tileFace
                            icon: modelData.icon
                            size: Theme.MEDIUM
                            color: modelData.danger ? "#ff5555" : Theme.textPrimary
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runAction(modelData.key)
                        }
                    }
                }
            }
        }

        SequentialAnimation {
            id: openAnim

            PauseAnimation {
                duration: 140
            }

            ParallelAnimation {
                SpringAnimation {
                    target: popupContent
                    property: "y"
                    from: root.startY
                    to: 0
                    spring: root.springPosY
                    damping: root.dampingPosY
                    epsilon: 0.001
                }
                SpringAnimation {
                    target: scaleTransform
                    property: "yScale"
                    from: root.startYScale
                    to: 1.0
                    spring: root.springY
                    damping: root.dampingY
                    epsilon: 0.001
                }
                SpringAnimation {
                    target: scaleTransform
                    property: "xScale"
                    from: root.startXScale
                    to: 1.0
                    spring: root.springX
                    damping: root.dampingX
                    epsilon: 0.001
                }
                NumberAnimation {
                    target: popupContent
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: root.fadeInDuration
                    easing.type: Easing.OutQuad
                }
            }
        }

        ParallelAnimation {
            id: closeAnim

            NumberAnimation {
                target: popupContent
                property: "y"
                to: root.startY
                duration: root.closeDuration
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: scaleTransform
                property: "yScale"
                to: root.startYScale
                duration: root.closeDuration + 10
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: scaleTransform
                property: "xScale"
                to: root.startXScale
                duration: root.closeDuration + 10
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: popupContent
                property: "opacity"
                to: 0.0
                duration: root.closeDuration - 10
                easing.type: Easing.InQuad
            }
            onFinished: root.visible = false
        }
    }
}
