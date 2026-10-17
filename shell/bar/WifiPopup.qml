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
    property bool isOpen: false

    property bool isScanning: false
    signal refreshRequested
    signal networkSelected(string ssid)

    property var rawNetworks: []
    property string lastConnectError: ""
    property string activeSsid: ""

    Shortcut {
        sequence: "Escape"
        enabled: root.isOpen
        onActivated: root.isOpen = false
    }

    ListModel {
        id: networkModel
    }

    function setInitialActiveSsid(ssid) {
        if (!ssid)
            return;
        root.activeSsid = ssid;
        var found = false;
        for (var i = 0; i < networkModel.count; ++i) {
            if (networkModel.get(i).ssid === ssid) {
                networkModel.setProperty(i, "connected", true);
                found = true;
            } else {
                networkModel.setProperty(i, "connected", false);
            }
        }
        if (!found) {
            networkModel.insert(0, {
                ssid: ssid,
                bssid: "",
                connected: true,
                connecting: false
            });
        }
    }

    function updateConnectedState(ssid, connected) {
        if (connected)
            root.activeSsid = ssid;
        else if (root.activeSsid === ssid)
            root.activeSsid = "";

        for (var i = 0; i < networkModel.count; ++i) {
            var item = networkModel.get(i);
            if (item.ssid === ssid) {
                networkModel.setProperty(i, "connected", connected);
                networkModel.setProperty(i, "connecting", false);
            } else if (connected) {
                networkModel.setProperty(i, "connected", false);
            }
        }

        if (connected) {
            var found = false;
            for (var j = 0; j < networkModel.count; ++j) {
                if (networkModel.get(j).ssid === ssid) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                networkModel.insert(0, {
                    ssid: ssid,
                    bssid: "",
                    connected: true,
                    connecting: false
                });
            }
        }
    }

    function collectLine(line) {
        line = line.trim();
        if (!line)
            return;
        var fields = [];
        var current = "";
        for (var i = 0; i < line.length; ++i) {
            if (line[i] === ":" && (i === 0 || line[i - 1] !== "\\")) {
                fields.push(current);
                current = "";
            } else {
                current += line[i];
            }
        }
        fields.push(current);

        if (fields.length < 3)
            return;
        var inUse = fields[0].indexOf("*") !== -1;
        var bssid = fields[1].replace(/\\/g, "").trim();
        var ssid = fields.slice(2).join(":").replace(/\\:/g, ":").trim();

        if (!ssid || !bssid)
            return;
        for (var j = 0; j < rawNetworks.length; ++j) {
            if (rawNetworks[j].ssid === ssid) {
                if (inUse) {
                    rawNetworks[j].connected = true;
                    rawNetworks[j].bssid = bssid;
                }
                return;
            }
        }

        rawNetworks.push({
            ssid: ssid,
            bssid: bssid,
            connected: inUse,
            connecting: false
        });
    }

    function finishScan() {
        rawNetworks.sort(function (a, b) {
            if (a.connected && !b.connected)
                return -1;
            if (!a.connected && b.connected)
                return 1;
            return a.ssid.localeCompare(b.ssid);
        });

        for (var i = networkModel.count - 1; i >= 0; --i) {
            var existingSsid = networkModel.get(i).ssid;
            var found = false;
            for (var j = 0; j < rawNetworks.length; ++j) {
                if (rawNetworks[j].ssid === existingSsid) {
                    found = true;
                    networkModel.setProperty(i, "bssid", rawNetworks[j].bssid);
                    if (networkModel.get(i).connected !== rawNetworks[j].connected && !networkModel.get(i).connecting) {
                        networkModel.setProperty(i, "connected", rawNetworks[j].connected);
                    }
                    rawNetworks.splice(j, 1);
                    break;
                }
            }
            if (!found && !networkModel.get(i).connected && !networkModel.get(i).connecting) {
                networkModel.remove(i);
            }
        }

        for (var k = 0; k < rawNetworks.length; ++k) {
            networkModel.append(rawNetworks[k]);
        }

        if (root.activeSsid) {
            for (var m = 0; m < networkModel.count; ++m) {
                if (networkModel.get(m).ssid === root.activeSsid) {
                    networkModel.setProperty(m, "connected", true);
                    break;
                }
            }
        }

        root.isScanning = false;
    }

    function scanNetworks() {
        if (scanProcess.running)
            return;
        isScanning = true;
        rawNetworks = [];
        refreshRequested();
        scanProcess.running = true;
    }

    function connectToNetwork(targetIndex, bssid, ssid) {
        if (connectProcess.running)
            connectProcess.running = false;

        for (var i = 0; i < networkModel.count; ++i) {
            if (i === targetIndex) {
                networkModel.setProperty(i, "connecting", true);
                networkModel.setProperty(i, "connected", false);
            } else {
                networkModel.setProperty(i, "connecting", false);
                if (networkModel.get(i).connected)
                    networkModel.setProperty(i, "connected", false);
            }
        }

        root.lastConnectError = "";
        connectProcess.targetIdx = targetIndex;
        connectProcess.targetSsid = ssid;
        connectProcess.command = ["nmcli", "d", "w", "c", bssid ? bssid : ssid];
        connectProcess.running = true;
    }

    grabFocus: false

    HyprlandFocusGrab {
        id: outsideClickGrab
        windows: [root]
        active: root.isOpen

        onCleared: {
            if (root.isOpen)
                root.isOpen = false;
        }
    }

    Process {
        id: activeWifiProc
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null | awk -F: '$2==\"wifi\" && $3==\"connected\" {print $4}' | head -n1"]
        running: false
        property string activeSsid: ""

        stdout: SplitParser {
            onRead: data => {
                activeWifiProc.activeSsid = data.trim();
            }
        }

        onExited: (code, status) => {
            if (code === 0 && activeWifiProc.activeSsid !== "") {
                root.setInitialActiveSsid(activeWifiProc.activeSsid);
            } else if (code === 0) {
                root.updateConnectedState(root.activeSsid, false);
            }
            activeWifiProc.activeSsid = "";
        }
    }

    Process {
        id: scanProcess
        command: ["nmcli", "-t", "-f", "IN-USE,BSSID,SSID", "device", "wifi", "list"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                root.collectLine(data);
            }
        }
        onExited: (code, status) => {
            root.finishScan();
        }
    }

    Process {
        id: connectProcess
        property int targetIdx: -1
        property string targetSsid: ""
        command: []
        running: false
        stderr: SplitParser {
            onRead: data => {
                root.lastConnectError += data + "\n";
            }
        }
        onExited: (code, status) => {
            if (code === 0) {
                if (targetIdx >= 0 && targetIdx < networkModel.count) {
                    networkModel.setProperty(targetIdx, "connecting", false);
                    networkModel.setProperty(targetIdx, "connected", true);
                    root.activeSsid = targetSsid;
                }
            } else {
                if (targetIdx >= 0 && targetIdx < networkModel.count) {
                    networkModel.setProperty(targetIdx, "connecting", false);
                    networkModel.setProperty(targetIdx, "connected", false);
                }
            }
            activeWifiProc.running = true;
            root.scanNetworks();
        }
    }

    Process {
        id: nmMonitor
        command: ["nmcli", "monitor"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                var line = data.trim();
                if (!line)
                    return;
                var connMatch = line.match(/has connection\s+'([^']+)'/i);
                if (connMatch) {
                    root.updateConnectedState(connMatch[1], true);
                    if (root.isOpen)
                        root.scanNetworks();
                    return;
                }

                if (/disconnected/i.test(line) || /state change:.*-> disconnected/i.test(line)) {
                    root.updateConnectedState(root.activeSsid, false);
                    if (root.isOpen)
                        root.scanNetworks();
                    return;
                }

                if (/NetworkManager is now in the/i.test(line) || /device \(wifi\)/i.test(line) || /Access point/i.test(line) || /state change/i.test(line) || /Connectivity/i.test(line)) {
                    if (!activeWifiProc.running)
                        activeWifiProc.running = true;
                    if (root.isOpen && !scanProcess.running)
                        root.scanNetworks();
                }
            }
        }

        onExited: (code, status) => {
            Qt.callLater(function () {
                if (!nmMonitor.running)
                    nmMonitor.running = true;
            });
        }
    }

    Component.onCompleted: {
        activeWifiProc.running = true;
    }

    property int openDelay: 190
    property real startY: -14
    property real startXScale: 0.82
    property real startYScale: 0.70

    property real springY: 4.2
    property real dampingY: 0.34
    property real springX: 4.5
    property real dampingX: 0.36
    property real springPosY: 4.2
    property real dampingPosY: 0.34

    property int fadeInDuration: 95
    property int closeDuration: 130
    property int staggerStep: 35

    function toggle() {
        isOpen = !isOpen;
    }

    onIsOpenChanged: {
        if (isOpen) {
            closeAnim.stop();
            openAnim.restart();
            if (!activeWifiProc.running)
                activeWifiProc.running = true;
        } else {
            openAnim.stop();
            closeAnim.restart();
            scanProcess.running = false;
            connectProcess.running = false;
            isScanning = false;
        }
    }

    anchor.window: targetWindow
    anchor.rect: anchorRect
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    implicitWidth: 320
    implicitHeight: 360
    color: "transparent"

    visible: root.isOpen || openAnim.running || closeAnim.running

    RectangularShadow {
        anchors.fill: popupContent
        radius: 20
        offset.y: 10
        blur: 36
        spread: -8
        color: "#00000080"
        opacity: popupContent.opacity
    }

    Item {
        id: popupContent
        property real radius: 20
        width: 270
        height: 320
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

        SequentialAnimation {
            id: openAnim

            onFinished: {
                if (root.isOpen)
                    root.scanNetworks();
            }

            PauseAnimation {
                duration: root.openDelay
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
                NumberAnimation {
                    target: headerRow
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: 160
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: divider
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: 160
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: bodyArea
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: 180
                    easing.type: Easing.OutCubic
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
        }

        ColumnLayout {
            id: innerContent
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            y: 0

            RowLayout {
                id: headerRow
                Layout.fillWidth: true

                Text {
                    text: "Wi-Fi"
                    color: Theme.textPrimary
                    font.pixelSize: 15
                    font.bold: true
                    renderType: Text.NativeRendering
                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    width: 28
                    height: 28
                    radius: Theme.metrics.radiusSm
                    color: refreshArea.containsMouse ? Theme.surfaceHover : Theme.surface

                    Behavior on color {
                        ColorAnimation {
                            duration: 70
                            easing.type: Easing.OutQuad
                        }
                    }

                    CielLoadingSpinner {
                        id: spinner
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        orbitRadius: 6.5
                        finalSize: 4.5
                        minDotSize: 2.0
                        maxDotSize: 5.5
                        color: root.isScanning ? Theme.textPrimary : Theme.textSecondary
                        finished: !root.isScanning
                    }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.isScanning)
                                root.scanNetworks();
                        }
                    }
                }
            }

            Rectangle {
                id: divider
                Layout.fillWidth: true
                height: 1
                color: Theme.surfaceHover
            }

            Item {
                id: bodyArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.centerIn: parent
                    visible: networkModel.count === 0
                    text: root.isScanning ? "Scanning networks..." : "No networks found"
                    color: Theme.textSecondary
                    font.pixelSize: 13
                    renderType: Text.NativeRendering
                }

                ListView {
                    id: networkListView
                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: networkModel
                    visible: networkModel.count > 0

                    boundsBehavior: Flickable.DragAndOvershootBounds

                    delegate: Rectangle {
                        id: rowDelegate
                        width: networkListView.width
                        height: 36
                        radius: Theme.metrics.radiusSm
                        color: rowMouse.containsMouse ? Theme.surfaceHover : "transparent"

                        property bool initialized: false
                        property bool isConnected: model.connected

                        onIsConnectedChanged: {
                            if (initialized && isConnected) {
                                rowWifi.triggerWave();
                                textNudgeAnim.restart();
                            }
                        }

                        Component.onCompleted: {
                            initialized = true;
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 70
                                easing.type: Easing.OutQuad
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            WifiButton {
                                id: rowWifi
                                interactive: false
                                animateOnClick: false
                                implicitWidth: 22
                                implicitHeight: 22
                                iconColor: model.connected ? Theme.textPrimary : Theme.textSecondary
                            }

                            Text {
                                id: ssidText
                                text: model.ssid
                                color: model.connected ? Theme.textPrimary : Theme.textSecondary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                renderType: Text.NativeRendering

                                transform: Translate {
                                    id: textTranslate
                                    x: 0
                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 180
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }

                            SequentialAnimation {
                                id: textNudgeAnim

                                NumberAnimation {
                                    target: textTranslate
                                    property: "x"
                                    from: 0
                                    to: 0.4
                                    duration: 120
                                    easing.type: Easing.OutQuad
                                }

                                SpringAnimation {
                                    target: textTranslate
                                    property: "x"
                                    from: 3.5
                                    to: 0
                                    spring: 4.5
                                    damping: 0.38
                                    epsilon: 0.001
                                }
                            }

                            CielCheckTick {
                                connecting: model.connecting
                                checked: model.connected
                                color: Theme.accent
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!model.connected && !model.connecting) {
                                    root.connectToNetwork(index, model.bssid, model.ssid);
                                    root.networkSelected(model.ssid);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
