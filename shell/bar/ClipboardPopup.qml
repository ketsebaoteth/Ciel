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
    // ListModel with roles: kind ("shot" | "record"), path, time
    property var store
    property bool isOpen: false
    property string expandedPath: ""

    readonly property int count: store ? store.count : 0
    readonly property int maxListHeight: 330

    // ---------- helpers ----------

    function actionsFor(kind) {
        if (kind === "shot") {
            return [
                {key: "copy", icon: "copy", label: "Copy", danger: false},
                {key: "open", icon: "arrow-square-out", label: "Open", danger: false},
                {key: "delete", icon: "trash", label: "Delete", danger: true},
                {key: "dismiss", icon: "x", label: "Dismiss", danger: false}
            ];
        }
        return [
            {key: "open", icon: "arrow-square-out", label: "Open", danger: false},
            {key: "delete", icon: "trash", label: "Delete", danger: true},
            {key: "dismiss", icon: "x", label: "Dismiss", danger: false}
        ];
    }

    function isCurrent(kind, path) {
        if (!capture)
            return false;
        return kind === "shot" ? capture.screenshotPath === path : capture.recordingPath === path;
    }

    function removeFromStore(path) {
        if (!store)
            return;
        for (var i = 0; i < store.count; ++i) {
            if (store.get(i).path === path) {
                store.remove(i);
                break;
            }
        }
        if (expandedPath === path)
            expandedPath = "";
    }

    function copyItem(kind, path) {
        if (kind !== "shot")
            return;
        if (isCurrent(kind, path) && capture) {
            capture.copyScreenshot();
        } else {
            copyProc.command = ["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", path];
            copyProc.running = true;
        }
    }

    function deleteItem(kind, path) {
        if (isCurrent(kind, path) && capture) {
            if (kind === "shot")
                capture.deleteScreenshot();
            else
                capture.deleteRecording();
        } else {
            rmProc.command = ["rm", "-f", path];
            rmProc.running = true;
        }
        removeFromStore(path);
    }

    function dismissItem(kind, path) {
        if (isCurrent(kind, path) && capture) {
            if (kind === "shot")
                capture.dismissScreenshot();
            else
                capture.dismissRecording();
        }
        removeFromStore(path);
    }

    function runAction(key, kind, path) {
        if (key === "copy") {
            copyItem(kind, path);
            root.isOpen = false;
        } else if (key === "open") {
            if (capture)
                capture.openFile(path);
            root.isOpen = false;
        } else if (key === "delete") {
            deleteItem(kind, path);
        } else if (key === "dismiss") {
            dismissItem(kind, path);
        }
    }

    // Left click: the most useful single action
    function primaryAction(kind, path) {
        runAction(kind === "shot" ? "copy" : "open", kind, path);
    }

    Process {
        id: copyProc
        command: []
        running: false
    }

    Process {
        id: rmProc
        command: []
        running: false
    }

    Connections {
        target: root.store

        function onCountChanged() {
            if (root.store.count === 0)
                root.isOpen = false;
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.isOpen
        onActivated: root.isOpen = false
    }

    // ---------- animation tuning ----------

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
            expandedPath = "";
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

    implicitWidth: 350
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

    component ActionTile: Item {
        id: tile

        property string icon: ""
        property string label: ""
        property bool danger: false

        signal activated

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
            text: tile.label
            color: Theme.textSecondary
            font.pixelSize: 10
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            renderType: Text.NativeRendering
        }

        CielIcon {
            anchors.centerIn: tileFace
            icon: tile.icon
            size: Theme.MEDIUM
            color: tile.danger ? "#ff5555" : Theme.textPrimary
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
    }

    Item {
        id: popupContent
        property real radius: 20
        width: 310
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
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                CielIcon {
                    icon: "clipboard"
                    size: Theme.SMALL
                    color: Theme.textPrimary
                }

                Text {
                    text: "Clipboard"
                    color: Theme.textPrimary
                    font.pixelSize: 15
                    font.bold: true
                    renderType: Text.NativeRendering
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: root.count + (root.count === 1 ? " item" : " items")
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.surfaceHover
            }

            Text {
                visible: root.count === 0
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                text: "Nothing here yet"
                color: Theme.textSecondary
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }

            ListView {
                id: list
                visible: root.count > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, root.maxListHeight)
                model: root.store
                spacing: 4
                clip: true
                interactive: contentHeight > root.maxListHeight
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: row

                    required property int index
                    required property string kind
                    required property string path
                    required property string time

                    readonly property bool expanded: root.expandedPath === path
                    readonly property var rowActions: root.actionsFor(kind)

                    width: ListView.view.width
                    height: 60 + (expanded ? 82 : 0)
                    clip: true

                    Behavior on height {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }

                    CielSquircle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: parent.height
                        radius: 14
                        color: (rowMouse.containsMouse || row.expanded) ? Theme.surfaceHover : Theme.surface // "transparent"
                        borderWidth: 0
                    }

                    // Thumbnail / kind tile
                    Item {
                        id: thumb
                        x: 6
                        y: 6
                        width: 48
                        height: 48

                        CielSquircle {
                            anchors.fill: parent
                            radius: 10
                            color: Theme.surfaceHover
                            borderWidth: 0
                        }

                        Image {
                            visible: row.kind === "shot"
                            anchors.fill: parent
                            anchors.margins: 2
                            source: row.kind === "shot" ? "file://" + row.path : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            smooth: true
                            sourceSize.width: 96
                        }

                        CielIcon {
                            visible: row.kind !== "shot"
                            anchors.centerIn: parent
                            icon: "video-camera"
                            size: Theme.MEDIUM
                            color: Theme.textPrimary
                        }
                    }

                    Column {
                        anchors.left: thumb.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        y: 30 - height / 2
                        spacing: 3

                        Text {
                            width: parent.width
                            text: row.path.split("/").pop()
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideMiddle
                            renderType: Text.NativeRendering
                        }

                        Text {
                            width: parent.width
                            text: (row.kind === "shot" ? "Screenshot" : "Recording") + " · " + row.time
                            color: Theme.textSecondary
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        x: 0
                        y: 0
                        width: parent.width
                        height: 60
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                root.expandedPath = row.expanded ? "" : row.path;
                            else
                                root.primaryAction(row.kind, row.path);
                        }
                    }

                    // Actions revealed by right click
                    GridLayout {
                        x: 8
                        y: 64
                        width: parent.width - 16
                        visible: row.expanded
                        columns: Math.max(1, row.rowActions.length)
                        columnSpacing: 8
                        rowSpacing: 8

                        Repeater {
                            model: row.rowActions

                            delegate: ActionTile {
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 74

                                icon: modelData.icon
                                label: modelData.label
                                danger: modelData.danger

                                onActivated: root.runAction(modelData.key, row.kind, row.path)
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.count > 0
                Layout.fillWidth: true
                text: "Click to copy / open · Right-click for more"
                color: Theme.textSecondary
                opacity: 0.7
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
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
