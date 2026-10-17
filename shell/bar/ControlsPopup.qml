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

    property real volumeLevel: 0.50
    property real brightnessLevel: 0.70
    property real targetVolume: 0.50
    property real targetBrightness: 0.70
    property real lastDispatchedVolume: -1.0
    property real lastDispatchedBrightness: -1.0

    property bool bluetoothEnabled: false
    property bool wifiEnabled: true
    property bool dndEnabled: false
    property bool airplaneEnabled: false
    property bool nightEnabled: false
    property bool micMuted: false
    property bool recording: false
    property bool caffeineEnabled: false

    property bool perAppPopupOpen: false

    Shortcut {
        sequence: "Escape"
        enabled: root.isOpen
        onActivated: root.isOpen = false
    }

    ListModel {
        id: appAudioModel
    }

    ListModel {
        id: sinkModel
    }

    function readHardwareLevels() {
        if (!volReader.running) {
            volReader.buffer = "";
            volReader.running = true;
        }
        if (!brightReader.running) {
            brightReader.buffer = "";
            brightReader.running = true;
        }
        if (!btReader.running) {
            btReader.buffer = "";
            btReader.running = true;
        }
        if (!wifiReader.running) {
            wifiReader.buffer = "";
            wifiReader.running = true;
        }
    }

    function applyVolume(val) {
        root.targetVolume = val;
        if (!volSetter.running)
            root.dispatchVolume();
    }

    function dispatchVolume() {
        root.lastDispatchedVolume = root.targetVolume;
        volSetter.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", root.targetVolume.toFixed(2)];
        volSetter.running = true;
    }

    function applyBrightness(val) {
        root.targetBrightness = val;
        if (!brightSetter.running)
            root.dispatchBrightness();
    }

    function dispatchBrightness() {
        root.lastDispatchedBrightness = root.targetBrightness;
        brightSetter.command = ["brightnessctl", "set", Math.round(root.targetBrightness * 100) + "%", "-q"];
        brightSetter.running = true;
    }

    function toggleBluetooth() {
        btToggle.command = ["bluetoothctl", "power", root.bluetoothEnabled ? "off" : "on"];
        btToggle.running = true;
        root.bluetoothEnabled = !root.bluetoothEnabled;
    }

    function toggleWifi() {
        wifiToggle.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"];
        wifiToggle.running = true;
        root.wifiEnabled = !root.wifiEnabled;
    }

    function toggleAirplane() {
        var next = !root.airplaneEnabled;
        airplaneToggle.command = ["nmcli", "radio", "all", next ? "off" : "on"];
        airplaneToggle.running = true;
        root.airplaneEnabled = next;
        if (next) {
            root.wifiEnabled = false;
            root.bluetoothEnabled = false;
        }
    }

    function refreshSinks() {
        if (sinkReader.running)
            return;
        sinkModel.clear();
        sinkReader.buffer = "";
        sinkReader.running = true;
    }

    function setDefaultSink(id) {
        if (!id)
            return;
        sinkSetter.command = ["wpctl", "set-default", id];
        sinkSetter.running = true;
    }

    function refreshAppVolumes() {
        if (appVolReader.running)
            return;
        appAudioModel.clear();
        appVolReader.buffer = "";
        appVolReader.running = true;
    }

    function appIconSource(appName) {
        const entry = appName ? DesktopEntries.heuristicLookup(appName) : null;

        if (entry && entry.icon)
            return Quickshell.iconPath(entry.icon, "application-x-executable");

        return null;
    }

    function setAppVolume(index, val) {
        if (index < 0 || index >= appAudioModel.count)
            return;
        var item = appAudioModel.get(index);
        appVolSetter.command = ["pactl", "set-sink-input-volume", item.id, Math.round(Math.max(0, Math.min(1, val)) * 100) + "%"];
        appVolSetter.running = true;
        appAudioModel.setProperty(index, "volume", Math.max(0, Math.min(1, val)));
    }

    Process {
        id: volSetter
        command: []
        running: false
        onExited: (code, status) => {
            if (Math.abs(root.targetVolume - root.lastDispatchedVolume) > 0.005)
                root.dispatchVolume();
        }
    }

    Process {
        id: brightSetter
        command: []
        running: false
        onExited: (code, status) => {
            if (Math.abs(root.targetBrightness - root.lastDispatchedBrightness) > 0.005)
                root.dispatchBrightness();
        }
    }

    Process {
        id: volReader
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print $2}' || pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o '[0-9]\\+%' | head -n1 | tr -d '%' | awk '{print $1/100}'"]
        running: false
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                volReader.buffer += data.trim();
            }
        }
        onExited: (code, status) => {
            if (code === 0 && volReader.buffer !== "") {
                var v = parseFloat(volReader.buffer);
                if (!isNaN(v)) {
                    root.volumeLevel = Math.max(0.0, Math.min(1.0, v));
                    root.targetVolume = root.volumeLevel;
                }
            }
            volReader.buffer = "";
        }
    }

    Process {
        id: brightReader
        command: ["sh", "-c", "brightnessctl g 2>/dev/null && brightnessctl m 2>/dev/null || (cat /sys/class/backlight/*/brightness 2>/dev/null | head -n1; cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -n1)"]
        running: false
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                brightReader.buffer += data.trim() + "\n";
            }
        }
        onExited: (code, status) => {
            if (code === 0 && brightReader.buffer.trim() !== "") {
                var lines = brightReader.buffer.trim().split("\n");
                if (lines.length >= 2) {
                    var cur = parseFloat(lines[0]);
                    var max = parseFloat(lines[1]);
                    if (!isNaN(cur) && !isNaN(max) && max > 0) {
                        root.brightnessLevel = Math.max(0.0, Math.min(1.0, cur / max));
                        root.targetBrightness = root.brightnessLevel;
                    }
                }
            }
            brightReader.buffer = "";
        }
    }

    Process {
        id: btReader
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo 1 || echo 0"]
        running: false
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                btReader.buffer += data.trim();
            }
        }
        onExited: (code, status) => {
            if (btReader.buffer !== "")
                root.bluetoothEnabled = btReader.buffer.trim() === "1";
            btReader.buffer = "";
        }
    }

    Process {
        id: btToggle
        command: []
        running: false
        onExited: (code, status) => {
            if (!btReader.running)
                btReader.running = true;
        }
    }

    Process {
        id: wifiReader
        command: ["sh", "-c", "nmcli radio wifi 2>/dev/null | head -n1"]
        running: false
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                wifiReader.buffer += data.trim();
            }
        }
        onExited: (code, status) => {
            var state = wifiReader.buffer.trim().toLowerCase();
            if (state === "enabled" || state === "disabled")
                root.wifiEnabled = state === "enabled";
            wifiReader.buffer = "";
        }
    }

    Process {
        id: wifiToggle
        command: []
        running: false
        onExited: (code, status) => {
            if (!wifiReader.running)
                wifiReader.running = true;
        }
    }

    Process {
        id: airplaneToggle
        command: []
        running: false
    }

    Process {
        id: sinkReader
        command: ["sh", "-c", "wpctl status 2>/dev/null | awk '/Sinks:/ { in_sinks=1; next } in_sinks && /Sink endpoints:|Sources:/ { exit } in_sinks && match($0, /[0-9]+\\./) { id=substr($0, RSTART, RLENGTH-1); prefix=substr($0, 1, RSTART-1); name=substr($0, RSTART+RLENGTH); sub(/[[:space:]]*\\[vol:.*/, \"\", name); gsub(/^[[:space:]]+|[[:space:]]+$/, \"\", name); printf \"%s|%s|%s\\n\", id, name, (prefix ~ /\\*/ ? 1 : 0) }'"]
        running: false
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                sinkReader.buffer += data + "\n";
            }
        }
        onExited: (code, status) => {
            var lines = sinkReader.buffer.trim().split("\n");
            for (var i = 0; i < lines.length; ++i) {
                var line = lines[i].trim();
                if (!line)
                    continue;
                var parts = line.split("|");
                if (parts.length >= 3) {
                    var name = parts[1].trim();
                    if (name === "")
                        continue;
                    sinkModel.append({
                        id: parts[0].trim(),
                        name: name,
                        isDefault: parts[2].trim() === "1"
                    });
                }
            }
            sinkReader.buffer = "";
        }
    }

    Process {
        id: sinkSetter
        command: []
        running: false
        onExited: (code, status) => {
            root.refreshSinks();
        }
    }

    Process {
        id: appVolReader
        command: ["sh", "-c", "pactl list sink-inputs 2>/dev/null | awk 'function emit() { name=app; if (name == \"\") name=binary; if (name == \"\") name=media; if (id ~ /^[0-9]+$/ && name != \"\" && channels > 0 && volume != \"\") printf \"%s|%s|%.4f\\n\", id, name, volume } /^Sink Input #/ { emit(); id=$3; sub(/^#/, \"\", id); app=\"\"; binary=\"\"; media=\"\"; volume=\"\"; channels=0; next } /^[[:space:]]*application.name = / { v=$0; sub(/^[[:space:]]*application.name = \"/, \"\", v); sub(/\".*/, \"\", v); app=v } /^[[:space:]]*application.process.binary = / { v=$0; sub(/^[[:space:]]*application.process.binary = \"/, \"\", v); sub(/\".*/, \"\", v); binary=v } /^[[:space:]]*media.name = / { v=$0; sub(/^[[:space:]]*media.name = \"/, \"\", v); sub(/\".*/, \"\", v); media=v } /^[[:space:]]*Sample Specification:/ { if (match($0, /[0-9]+ch/)) { c=substr($0, RSTART, RLENGTH-2); channels=c+0 } } /^[[:space:]]*Volume:/ { if (match($0, /[0-9]+%/)) { volume=substr($0, RSTART, RLENGTH-1)/100 } } END { emit() }'"]
        running: false
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                appVolReader.buffer += data + "\n";
            }
        }
        onExited: (code, status) => {
            appAudioModel.clear();
            if (code === 0 && appVolReader.buffer.trim() !== "") {
                var lines = appVolReader.buffer.trim().split("\n");
                for (var i = 0; i < lines.length; ++i) {
                    var line = lines[i].trim();
                    if (!line)
                        continue;
                    var parts = line.split("|");
                    if (parts.length < 3 || !/^\d+$/.test(parts[0].trim()) || parts[1].trim() === "")
                        continue;
                    var v = parseFloat(parts[2]);
                    if (isNaN(v) || !isFinite(v))
                        continue;
                    appAudioModel.append({
                        id: parts[0].trim(),
                        name: parts[1].trim(),
                        volume: Math.max(0.0, Math.min(1.0, v))
                    });
                }
            }
            appVolReader.buffer = "";
        }
    }

    Process {
        id: appVolSetter
        command: []
        running: false
    }

    Process {
        id: screenshotProc
        command: ["sh", "-c", "mkdir -p \"$HOME/Pictures\" && (grim \"$HOME/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png\" || gnome-screenshot -f \"$HOME/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png\" || spectacle -b -n -o \"$HOME/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png\")"]
        running: false
    }

    Process {
        id: recordProc
        command: ["sh", "-c", "mkdir -p \"$HOME/Videos\" && wf-recorder -f \"$HOME/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4\""]
        running: false
    }

    Process {
        id: micProc
        command: []
        running: false
    }

    Process {
        id: lockProc
        command: ["loginctl", "lock-session"]
        running: false
    }

    function takeScreenshot() {
        if (!screenshotProc.running)
            screenshotProc.running = true;
    }

    function toggleRecording() {
        if (root.recording) {
            recordProc.running = false;
            root.recording = false;
        } else {
            recordProc.running = true;
            root.recording = true;
        }
    }

    function toggleMic() {
        root.micMuted = !root.micMuted;
        micProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", root.micMuted ? "1" : "0"];
        micProc.running = true;
    }

    function lockSession() {
        if (!lockProc.running)
            lockProc.running = true;
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
            root.readHardwareLevels();
        } else {
            openAnim.stop();

            if (visible)
                closeAnim.restart();
            else
                closeAnim.stop();

            root.perAppPopupOpen = false;
        }
    }

    anchor.window: targetWindow
    anchor.rect: anchorRect
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    implicitWidth: 400
    implicitHeight: popupContent.height + 50
    color: "transparent"

    grabFocus: false

    visible: root.isOpen || openAnim.running || closeAnim.running

    HyprlandFocusGrab {
        id: outsideClickGrab
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
        width: 340
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

            Text {
                text: "Control Center"
                color: Theme.textPrimary
                font.pixelSize: 15
                font.bold: true
                renderType: Text.NativeRendering
            }

            Item {
                Layout.fillWidth: true
                height: 42

                CielSlider {
                    id: volumeSlider
                    anchors.fill: parent
                    value: root.volumeLevel
                    onSliderMoved: val => root.applyVolume(val)

                    VolumeIcon {
                        value: root.volumeLevel
                        color: Theme.textPrimary
                    }
                }

                MouseArea {
                    id: volumeRightClick
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: function (mouse) {
                        if (mouse.button === Qt.RightButton) {
                            root.refreshSinks();
                            audioContextMenu.close();
                            audioContextMenu.popup(mouse.x, mouse.y, volumeRightClick);
                        }
                    }
                }

                CielContextMenu {
                    id: audioContextMenu

                    CielMenuItem {
                        text: "Audio settings"
                        icon: "gear-six"
                        onTriggered: {
                            audioContextMenu.close();
                        }
                    }

                    CielMenuSub {
                        id: devicesButton
                        text: "Devices"
                        icon: "faders-horizontal"

                        CielMenuItem {
                            text: "No audio devices found"
                            visible: sinkModel.count === 0
                            enabled: false
                        }

                        Repeater {
                            model: sinkModel
                            delegate: CielMenuItem {
                                text: model.name
                                icon: model.isDefault ? "check" : "speaker"
                                onTriggered: root.setDefaultSink(model.id)
                            }
                        }
                    }

                    CielMenuItem {
                        text: "Per App Volumes"
                        icon: "speaker-high"
                        onTriggered: {
                            root.isOpen = false;
                            audioContextMenu.close();
                            root.perAppPopupOpen = true;
                        }
                    }
                }
            }

            CielSlider {
                Layout.fillWidth: true
                height: 42
                value: root.brightnessLevel
                onSliderMoved: val => root.applyBrightness(val)

                BrightnessIcon {
                    value: root.brightnessLevel
                    color: Theme.textPrimary
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: [
                        {
                            key: "wifi",
                            icon: "wifi-high",
                            label: "Wi-Fi",
                            active: root.wifiEnabled
                        },
                        {
                            key: "bt",
                            icon: "bluetooth",
                            label: "Bluetooth",
                            active: root.bluetoothEnabled
                        },
                        {
                            key: "plane",
                            icon: "airplane",
                            label: "Airplane",
                            active: root.airplaneEnabled
                        },
                        {
                            key: "dnd",
                            icon: "bell-slash",
                            label: "Do Not Disturb",
                            active: root.dndEnabled
                        },
                        {
                            key: "night",
                            icon: "moon",
                            label: "Night Light",
                            active: root.nightEnabled
                        },
                        {
                            key: "shot",
                            icon: "camera",
                            label: "Screenshot",
                            active: false
                        },
                        {
                            key: "record",
                            icon: "record",
                            label: "Screen Record",
                            active: root.recording
                        },
                        {
                            key: "mic",
                            icon: "microphone",
                            label: "Mic",
                            active: root.micMuted
                        },
                        {
                            key: "lock",
                            icon: "lock",
                            label: "Lock",
                            active: false
                        },
                        {
                            key: "caffeine",
                            icon: "coffee",
                            label: "Keep Awake",
                            active: root.caffeineEnabled
                        }
                    ]

                    delegate: Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        implicitHeight: 74

                        CielSquircle {
                            id: tileFace
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 48
                            radius: 16
                            color: modelData.active ? Theme.accent : (tileMouse.containsMouse ? Theme.surface : Theme.surfaceHover)
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
                            color: modelData.active ? Theme.surface : Theme.textPrimary
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.key === "wifi")
                                    root.toggleWifi();
                                else if (modelData.key === "bt")
                                    root.toggleBluetooth();
                                else if (modelData.key === "plane")
                                    root.toggleAirplane();
                                else if (modelData.key === "dnd")
                                    root.dndEnabled = !root.dndEnabled;
                                else if (modelData.key === "night")
                                    root.nightEnabled = !root.nightEnabled;
                                else if (modelData.key === "shot")
                                    root.takeScreenshot();
                                else if (modelData.key === "record")
                                    root.toggleRecording();
                                else if (modelData.key === "mic")
                                    root.toggleMic();
                                else if (modelData.key === "lock")
                                    root.lockSession();
                                else if (modelData.key === "caffeine")
                                    root.caffeineEnabled = !root.caffeineEnabled;
                            }
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

    PanelWindow {
        id: perAppLayer
        visible: root.perAppPopupOpen || appOpenAnim.running || appCloseAnim.running
        screen: root.targetWindow ? root.targetWindow.screen : null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        aboveWindows: true

        MouseArea {
            anchors.fill: parent
            enabled: root.perAppPopupOpen

            onClicked: {
                root.perAppPopupOpen = false;
            }
        }

        Rectangle {
            color: Theme.background

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: mouse => mouse.accepted = true
            }
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            anchors.fill: parent
            color: "#00000066"
            opacity: root.perAppPopupOpen ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation {
                    duration: root.perAppPopupOpen ? root.fadeInDuration : root.closeDuration
                    easing.type: root.perAppPopupOpen ? Easing.OutQuad : Easing.InQuad
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.perAppPopupOpen
            onClicked: root.perAppPopupOpen = false
        }

        Item {
            id: perAppCard
            width: 460
            height: 420
            anchors.centerIn: parent
            opacity: 0.0

            transform: [
                Scale {
                    id: appCardScale
                    origin.x: perAppCard.width / 2
                    origin.y: perAppCard.height / 2
                    xScale: root.startXScale
                    yScale: root.startYScale
                },
                Translate {
                    id: appCardTranslate
                    y: root.startY
                }
            ]

            RectangularShadow {
                anchors.fill: parent
                radius: 20
                offset.y: 10
                blur: 36
                spread: -8
                color: "#00000080"
                opacity: perAppCard.opacity
            }

            CielSquircle {
                anchors.fill: parent
                radius: 20
                color: Theme.surface
                borderColor: Theme.surfaceHover
                borderWidth: 1
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "App Volumes"
                        color: Theme.textPrimary
                        font.pixelSize: 15
                        font.bold: true
                        renderType: Text.NativeRendering
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 12
                        color: closeMouse.containsMouse ? Theme.surfaceHover : "transparent"

                        CielIcon {
                            anchors.centerIn: parent
                            icon: "x"
                            size: Theme.XSMALL
                            color: Theme.textSecondary
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.perAppPopupOpen = false
                        }
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: appRow.implicitWidth
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    visible: appAudioModel.count > 0

                    Row {
                        id: appRow
                        spacing: 18
                        height: parent.height

                        Repeater {
                            model: appAudioModel

                            ColumnLayout {
                                width: 72
                                height: parent.height
                                spacing: 6

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 48

                                    CielSlider {
                                        width: Math.max(42, parent.height - 8)
                                        height: 42
                                        anchors.centerIn: parent
                                        rotation: -90
                                        value: model.volume
                                        onSliderMoved: val => root.setAppVolume(index, val)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: Math.round(model.volume * 100) + "%"
                                    color: Theme.textPrimary
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    renderType: Text.NativeRendering
                                }

                                Image {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: root.appIconSource(model.name)
                                    source: root.appIconSource(model.name)
                                    sourceSize.width: 32
                                    sourceSize.height: 32
                                    width: 32
                                    height: 32
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }

                                CielIcon {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: !root.appIconSource(model.name)
                                    icon: "squares-four"
                                    size: Theme.MEDIUM
                                    color: Theme.textSecondary
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.name
                                    color: Theme.textSecondary
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    renderType: Text.NativeRendering
                                }
                            }
                        }
                    }
                }

                Item {
                    visible: appAudioModel.count === 0
                    Layout.alignment: Qt.AlignCenter
                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    Text {
                        anchors.centerIn: parent
                        visible: appAudioModel.count === 0
                        text: "No active audio streams"
                        color: Theme.textSecondary
                        font.pixelSize: 13
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        ParallelAnimation {
            id: appOpenAnim

            SpringAnimation {
                target: appCardTranslate
                property: "y"
                from: root.startY
                to: 0
                spring: root.springPosY
                damping: root.dampingPosY
                epsilon: 0.001
            }
            SpringAnimation {
                target: appCardScale
                property: "yScale"
                from: root.startYScale
                to: 1.0
                spring: root.springY
                damping: root.dampingY
                epsilon: 0.001
            }
            SpringAnimation {
                target: appCardScale
                property: "xScale"
                from: root.startXScale
                to: 1.0
                spring: root.springX
                damping: root.dampingX
                epsilon: 0.001
            }
            NumberAnimation {
                target: perAppCard
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: root.fadeInDuration
                easing.type: Easing.OutQuad
            }
        }

        ParallelAnimation {
            id: appCloseAnim

            NumberAnimation {
                target: appCardTranslate
                property: "y"
                to: root.startY
                duration: root.closeDuration
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: appCardScale
                property: "yScale"
                to: root.startYScale
                duration: root.closeDuration + 10
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: appCardScale
                property: "xScale"
                to: root.startXScale
                duration: root.closeDuration + 10
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: perAppCard
                property: "opacity"
                to: 0.0
                duration: root.closeDuration - 10
                easing.type: Easing.InQuad
            }
        }
    }

    onPerAppPopupOpenChanged: {
        if (perAppPopupOpen) {
            appCloseAnim.stop();
            root.refreshAppVolumes();
            appOpenAnim.restart();
        } else {
            appOpenAnim.stop();
            appCloseAnim.restart();
        }
    }
}
