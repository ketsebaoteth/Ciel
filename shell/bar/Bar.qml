//@ pragma UseQApplication

import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import QtQml.Models
import Quickshell.Hyprland
import QtQuick.Effects
import Ciel.Ui

PanelWindow {
    id: bar

    property int paddingHorizontal: 12
    property int paddingVertical: 8
    property string hyprBuffer: ""
    property var workspaceApps: ({})
    property var selectedTrayItem: null

    anchors.top: true
    margins.top: 5
    implicitWidth: content.implicitWidth + (paddingHorizontal * 2) + chassisWidthNudge
    implicitHeight: content.implicitHeight + (paddingVertical * 2)
    color: "transparent"

    Behavior on implicitWidth {
        SequentialAnimation {
            NumberAnimation {
                to: targetValue + (targetValue >= bar.implicitWidth ? 3 : -3)
                duration: 85
                easing.type: Easing.OutCubic
            }
    
            SpringAnimation {
                to: targetValue
                spring: 38
                damping: 0.82
                mass: 1.0
                epsilon: 0.2
            }
        }
    }

    WlrLayershell.keyboardFocus: appLauncher.isOpen ? WlrLayershell.OnDemand : WlrLayershell.None

    ListModel {
        id: workspaceModel
    }

    CaptureService {
        id: captureService
    }

    ListModel {
        id: clipboardModel
    }
    
    function addClip(kind, path) {
        if (!path)
            return;
        for (var i = 0; i < clipboardModel.count; ++i) {
            if (clipboardModel.get(i).path === path)
                return;
        }
        clipboardModel.insert(0, {
            kind: kind,
            path: path,
            time: Qt.formatTime(new Date(), "h:mm AP")
        });
    }
    
    function syncShot() {
        if (captureService.hasScreenshot)
            bar.addClip("shot", captureService.screenshotPath);
    }
    
    Connections {
        target: captureService
    
        function onScreenshotPathChanged() { bar.syncShot(); }
        function onHasScreenshotChanged() { bar.syncShot(); }
    
        function onRecordingChanged() {
            if (!captureService.recording) {
                recordPopup.isOpen = false;
                bar.addClip("record", captureService.recordingPath);
            }
        }
    }
    
    Component.onCompleted: syncShot()

    function formatDuration(s) {
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    property int focusedWorkspaceId: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id >= 1) ? Hyprland.focusedWorkspace.id : 1
    readonly property int workspacesPerPage: 5
    readonly property int pageStart: Math.min(Math.floor((Math.max(focusedWorkspaceId, 1) - 1) / workspacesPerPage), 1) * workspacesPerPage + 1
    property int chassisWidthNudge: 0

    onFocusedWorkspaceIdChanged: {
        chassisWidthNudge = 3;
        chassisReactionReset.restart();
    }

    Timer {
        id: chassisReactionReset
        interval: 120
        repeat: false

        onTriggered: {
            bar.chassisWidthNudge = 0;
        }
    }

    function syncWorkspaces(rows) {
        var nextApps = {};
        var modelRows = [];

        for (var i = 0; i < rows.length; ++i) {
            var key = rows[i].workspaceKey || ("workspace-" + rows[i].workspaceId);

            nextApps[key] = rows[i].apps || [];

            modelRows.push({
                workspaceKey: key,
                workspaceId: rows[i].workspaceId,
                isActive: !!rows[i].isActive,
                isEmpty: !!rows[i].isEmpty
            });
        }

        bar.workspaceApps = nextApps;

        while (workspaceModel.count > modelRows.length) {
            workspaceModel.remove(workspaceModel.count - 1);
        }

        for (var j = 0; j < modelRows.length; ++j) {
            if (j < workspaceModel.count) {
                workspaceModel.set(j, modelRows[j]);
            } else {
                workspaceModel.append(modelRows[j]);
            }
        }
    }

    function appIcon(appId) {
        if (!appId)
            return "";

        const entry = DesktopEntries.heuristicLookup(appId);
        if (!entry)
            return "";

        return Quickshell.iconPath(entry.icon, true);
    }

    function parseHyprClients(text) {
        try {
            var clients = JSON.parse(text);
            var wsMap = {};
            var first = bar.pageStart;
            var last = first + bar.workspacesPerPage - 1;
            var focusedWs = bar.focusedWorkspaceId;

            for (var i = 0; i < clients.length; ++i) {
                var c = clients[i];
                var wsId = c.workspace ? c.workspace.id : null;

                if (wsId === null || wsId < first || wsId > last)
                    continue;

                if (!wsMap[wsId]) {
                    wsMap[wsId] = {
                        workspaceId: wsId,
                        apps: [],
                        isActive: false,
                        isEmpty: false
                    };
                }

                wsMap[wsId].apps.push({
                    appId: c.initialClass || c.class || "",
                    title: c.title || "",
                    address: c.address || "",
                    isFocused: c.focusHistoryID === 0
                });
            }

            var list = [];

            for (var w = first; w <= last; ++w) {
                if (wsMap[w] && wsMap[w].apps.length > 0) {
                    wsMap[w].apps.sort(function (a, b) {
                        if (a.isFocused && !b.isFocused)
                            return -1;

                        if (!a.isFocused && b.isFocused)
                            return 1;

                        return 0;
                    });

                    wsMap[w].isActive = (w === focusedWs);
                    list.push(wsMap[w]);
                } else {
                    list.push({
                        workspaceId: w,
                        apps: [],
                        isActive: (w === focusedWs),
                        isEmpty: true
                    });
                }
            }

            bar.syncWorkspaces(list);
        } catch (e) {
            fallbackGrouping();
        }
    }

    function fallbackGrouping() {
        var raw = ToplevelManager.toplevels;
        var map = {};

        for (var i = 0; i < raw.length; ++i) {
            var tl = raw[i];
            var key = tl.appId || String(i);

            if (!map[key]) {
                map[key] = {
                    workspaceKey: "fallback-" + key,
                    workspaceId: 1,
                    apps: [],
                    isActive: false,
                    isEmpty: false
                };
            }

            map[key].apps.push({
                appId: tl.appId,
                title: tl.title,
                address: "",
                isFocused: tl.activated,
                toplevel: tl
            });

            if (tl.activated)
                map[key].isActive = true;
        }

        var arr = [];

        for (var k in map)
            arr.push(map[k]);

        bar.syncWorkspaces(arr);
    }

    function switchToWorkspace(wsId, address, toplevel) {
        if (address) {
            dispatchProc.command = ["hyprctl", "--batch", "dispatch workspace " + wsId + " ; dispatch focuswindow address:" + address];
            dispatchProc.running = true;
        } else {
            dispatchProc.command = ["hyprctl", "dispatch", "workspace", String(wsId)];
            dispatchProc.running = true;
        }

        if (toplevel && toplevel.activate)
            toplevel.activate();
    }

    Process {
        id: dispatchProc
        command: []
        running: false
    }

    Process {
        id: hyprWatcher
        command: ["hyprctl", "clients", "-j"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                bar.hyprBuffer += data + "\n";
            }
        }

        onExited: (code, status) => {
            if (code === 0 && bar.hyprBuffer.trim() !== "")
                bar.parseHyprClients(bar.hyprBuffer);

            bar.hyprBuffer = "";
        }
    }

    Timer {
        interval: 350
        running: true
        repeat: true

        onTriggered: {
            if (!hyprWatcher.running) {
                bar.hyprBuffer = "";
                hyprWatcher.running = true;
            }
        }
    }

    Instantiator {
        model: ToplevelManager.toplevels

        onObjectAdded: {
            if (!hyprWatcher.running) {
                bar.hyprBuffer = "";
                hyprWatcher.running = true;
            }
        }

        onObjectRemoved: {
            if (!hyprWatcher.running) {
                bar.hyprBuffer = "";
                hyprWatcher.running = true;
            }
        }

        delegate: QtObject {
            property bool act: modelData ? modelData.activated : false

            onActChanged: {
                if (!hyprWatcher.running) {
                    bar.hyprBuffer = "";
                    hyprWatcher.running = true;
                }
            }
        }
    }

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged() {
            if (!hyprWatcher.running) {
                bar.hyprBuffer = "";
                hyprWatcher.running = true;
            }
        }
    }

    component Separator: Rectangle {
        implicitWidth: 1
        implicitHeight: 14

        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

        color: Theme.surfaceHover
    }

    component CaptureChip: Item {
        id: chip

        property string icon: ""
        property string label: ""
        property color tint: Theme.textPrimary
        property bool pulsing: false
	property int badge: 0

        signal clicked(var mouse)

        implicitWidth: chipRow.implicitWidth + 14
        implicitHeight: 28

        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: chipMouse.containsMouse ? Theme.surfaceHover : "transparent"
        }

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            CielIcon {
                id: chipIcon
                anchors.verticalCenter: parent.verticalCenter
                icon: chip.icon
                size: Theme.SMALL
                color: chip.tint

                SequentialAnimation on opacity {
                    running: chip.pulsing
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
                            chipIcon.opacity = 1.0;
                    }
                }
            }

            Text {
                visible: chip.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: Theme.textSecondary
                font.pixelSize: 12
                font.weight: Font.Medium
                renderType: Text.NativeRendering
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => chip.clicked(mouse)
        }

	Rectangle {
	    visible: chip.badge > 0
	    anchors.top: parent.top
	    anchors.right: parent.right
	    anchors.topMargin: -2
	    height: 14
	    width: Math.max(14, badgeText.implicitWidth + 6)
	    radius: 7
	    color: Theme.accent

	    Text {
                id: badgeText
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                text: chip.badge > 99 ? "99+" : String(chip.badge)
                color: Theme.surface
                font.pixelSize: 9
                font.bold: true
                renderType: Text.NativeRendering
	    }
	}
    }

    CielSquircle {
        anchors.fill: parent
        radius: parent.height
        color: Theme.surface
        borderColor: Theme.surfaceHover
        borderWidth: 1
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Theme.metrics.spacingSm
	width: Math.min(implicitWidth, Math.max(0, bar.width - bar.paddingHorizontal * 2))
	clip: true

        WinButton {
            id: winButton
            onClicked: appLauncher.toggle()
        }

        Separator {}

        Item {
            id: iconStrip

            implicitWidth: iconRow.implicitWidth
            implicitHeight: 34

            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight

	    Behavior on implicitWidth {
	        SequentialAnimation {
	    	    NumberAnimation {
	    	        to: targetValue + (targetValue >= iconStrip.implicitWidth ? 2 : -2)
	    	        duration: 65
	    	        easing.type: Easing.OutCubic
	    	    }

	    	    SpringAnimation {
	    	        to: targetValue
	    	        spring: 50 
	    	        damping: 0.8 
	    	        mass: 1.0
	    	        epsilon: 0.25
	    	    }
	        }
	    }

            Row {
                id: iconRow

                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.metrics.spacingSm

                Repeater {
                    id: workspaceRepeater
                    model: workspaceModel

                    delegate: Item {
                        id: delegateItem

                        required property string workspaceKey
                        required property int workspaceId
                        required property bool isActive
                        required property bool isEmpty

                        property var apps: bar.workspaceApps[workspaceKey] || []
                        property int count: apps.length
                        property int extraOffset: isEmpty ? 0 : Math.min(count - 1, 2) * 5

                        property int focusWidth: isActive ? 3 : 0

                        implicitWidth: 34 + extraOffset + focusWidth
                        implicitHeight: 34

                        width: implicitWidth
                        height: implicitHeight

                        Behavior on width {
                            CielSpring {
                                damping: 0.28
                                spring: 3.0
                                mass: 1.0
                                epsilon: 0.001
                            }
                        }

                        property real itemCenterX: iconRow.x + x + (width / 2)

                        property real distance: Math.abs(dockHoverArea.mouseX - itemCenterX)

                        property real normalizedDist: Math.min(distance / 72, 1.0)

                        property real influence: dockHoverArea.containsMouse ? 0.5 * (1.0 + Math.cos(Math.PI * normalizedDist)) : 0

                        Item {
                            id: scalableContent

                            anchors.fill: parent
                            transformOrigin: Item.Center

                            scale: 1.0 + (delegateItem.influence * 0.15)

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 180
                                    easing.type: Easing.OutQuad
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 7

                                color: Theme.textPrimary
                                opacity: delegateItem.influence * 0.08

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent

                                visible: delegateItem.isEmpty

                                width: 6
                                height: 6
                                radius: 3

                                color: delegateItem.isActive ? Theme.textPrimary : Theme.textSecondary

                                opacity: delegateItem.isActive ? 0.9 : 0.4

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 180
                                    }
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 180
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }

                            Item {
                                anchors.centerIn: parent

                                visible: !delegateItem.isEmpty

                                width: 26 + delegateItem.extraOffset
                                height: 26

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutQuad
                                    }
                                }

                                Repeater {
                                    model: Math.min(delegateItem.count, 3)

                                    delegate: Item {
                                        id: appIconDelegate

                                        z: -index
                                        width: 26
                                        height: 26

                                        property string appId: delegateItem.apps[index].appId || ""

                                        property string displayedAppId: appId

                                        property real stackOpacity: index === 0 ? 1.0 : (index === 1 ? 0.65 : 0.38)

                                        x: index * 5
                                        y: -(index * 1.5)
                                        scale: 1.0 - (index * 0.08)
                                        opacity: 0

                                        Component.onCompleted: enterAnimation.start()

                                        ParallelAnimation {
                                            id: enterAnimation

                                            NumberAnimation {
                                                target: appIconDelegate
                                                property: "scale"
                                                from: 0.72
                                                to: 1.0 - (index * 0.08)
                                                duration: 180
                                                easing.type: Easing.OutQuad
                                            }

                                            NumberAnimation {
                                                target: appIconDelegate
                                                property: "opacity"
                                                from: 0
                                                to: appIconDelegate.stackOpacity
                                                duration: 200
                                                easing.type: Easing.OutQuad
                                            }
                                        }

                                        onAppIdChanged: {
                                            if (appIconDelegate.displayedAppId !== appIconDelegate.appId)
                                                swapAnimation.restart();
                                        }

                                        SequentialAnimation {
                                            id: swapAnimation

                                            NumberAnimation {
                                                target: appIconDelegate
                                                property: "opacity"
                                                to: 0
                                                duration: 90
                                                easing.type: Easing.InQuad
                                            }

                                            ScriptAction {
                                                script: {
                                                    appIconDelegate.displayedAppId = appIconDelegate.appId;
                                                }
                                            }

                                            NumberAnimation {
                                                target: appIconDelegate
                                                property: "opacity"
                                                to: appIconDelegate.stackOpacity
                                                duration: 150
                                                easing.type: Easing.OutQuad
                                            }
                                        }

                                        Image {
                                            id: appImg

                                            anchors.fill: parent
                                            fillMode: Image.PreserveAspectFit
                                            sourceSize: Qt.size(64, 64)

                                            source: bar.appIcon(appIconDelegate.displayedAppId)

                                            Timer {
                                                interval: 200
                                                running: appImg.source == ""
                                                repeat: true

                                                onTriggered: {
                                                    var s = bar.appIcon(appIconDelegate.displayedAppId);

                                                    if (s !== "") {
                                                        appImg.source = s;
                                                        stop();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -1

                            width: 3.5
                            height: 3.5
                            radius: 1.75

                            color: Theme.accent
                            opacity: delegateItem.isActive ? 0.9 : 0.0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: dockHoverArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: mouse => {
                    const p = iconStrip.mapToItem(iconRow, mouse.x, mouse.y);

                    let target = null;

                    for (let i = 0; i < workspaceRepeater.count; ++i) {
                        const child = workspaceRepeater.itemAt(i);

                        if (child && p.x >= child.x && p.x <= child.x + child.width && p.y >= child.y && p.y <= child.y + child.height) {
                            target = child;
                            break;
                        }
                    }

                    if (target) {
                        const ws = target;
                        const topApp = ws.apps.length > 0 ? ws.apps[0] : null;

                        bar.switchToWorkspace(ws.workspaceId, topApp ? topApp.address : "", topApp ? topApp.toplevel : null);
                    }
                }
            }
        }

        Separator {}

        Text {
            id: clock

            color: Theme.textSecondary
            text: Qt.formatTime(new Date(), "h:mm AP")

            font.pixelSize: 13
            font.weight: Font.Medium
            renderType: Text.NativeRendering

            Timer {
                interval: 1000
                running: true
                repeat: true

                onTriggered: {
                    clock.text = Qt.formatTime(new Date(), "h:mm AP");
                }
            }
        }

        WifiButton {
            id: wifiButton
            onClicked: wifiPopup.toggle()
        }

        BatteryIndicator {
            id: batteryIndicator
        }

        Separator {}

        RowLayout {
            id: traySection

            spacing: 6

            Repeater {
                id: trayRepeater
                model: SystemTray.items

                delegate: Item {
                    id: trayIconItem

                    required property var modelData

                    property var trayItem: modelData
                    property string resolvedIcon: trayItem && trayItem.icon ? String(trayItem.icon) : ""

                    implicitWidth: 28
                    implicitHeight: 28

                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: trayMouseArea.containsMouse ? Theme.surfaceHover : "transparent"
                    }

                    Image {
                        id: trayIcon

                        anchors.centerIn: parent
                        width: 20
                        height: 20

                        source: trayIconItem.resolvedIcon
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize: Qt.size(48, 48)

                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: trayIcon.status !== Image.Ready
                        text: "●"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: trayMouseArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                        function openMenu() {
                            const item = trayIconItem.trayItem;
                        
                            if (!item || !item.hasMenu)
                                return;
                        
                            if (trayPopup.isOpen && bar.selectedTrayItem === item) {
                                trayPopup.isOpen = false;
                                return;
                            }
                        
                            const p = trayIconItem.mapToItem(null, 0, 0);

			    // DEBUG: the native menu (only for debug purposes)
			    // const p = trayIconItem.mapToItem(null, 0, trayIconItem.height + 6);
			    // item.display(bar, Math.round(p.x), Math.round(p.y));
                        
                            bar.selectedTrayItem = item;
                            trayPopup.anchorRect = Qt.rect(p.x, p.y + 6, trayIconItem.width, trayIconItem.height);
                            trayPopup.isOpen = true;
                        }

                        onClicked: mouse => {
                            const item = trayIconItem.trayItem;
                        
                            if (!item)
                                return;
                        
                            if (mouse.button === Qt.LeftButton) {
                                if (item.onlyMenu)
                                    openMenu(); // openNativeMenu();
                                else
                                    item.activate();
                            } else if (mouse.button === Qt.RightButton) {
                                openMenu(); // openNativeMenu();
                            } else if (mouse.button === Qt.MiddleButton) {
                                item.secondaryActivate();
                            }
                        }

                        onWheel: wheel => {
                            const item = trayIconItem.trayItem;

                            if (item)
                                item.scroll(wheel.angleDelta.y, false);
                        }
                    }
                }
            }
        }

        Separator {
            visible: trayRepeater.count > 0
        }

	CaptureChip {
	    id: clipboardChip
	    visible: clipboardModel.count > 0
	    icon: "clipboard"
	    badge: clipboardModel.count
	
	    onClicked: mouse => clipboardPopup.toggle()
	}
	
	CaptureChip {
	    id: recordChip
	    visible: captureService.recording
	    icon: "record"
	    tint: "#ff5555"
	    pulsing: true
	    label: bar.formatDuration(captureService.recordSeconds)
	
	    onClicked: mouse => recordPopup.toggle()
	}
	
	Separator {
	    visible: clipboardModel.count > 0 || captureService.recording
	}

        // Separator {
        //     visible: captureService.hasScreenshot || captureService.recording || captureService.hasRecording
        // }

        ControlsButton {
            id: controlsButton
            onClicked: controlsPopup.toggle()
        }
    }

    WifiPopup {
        id: wifiPopup

        targetWindow: bar

        anchorRect: Qt.rect(content.x + wifiButton.x, content.y + wifiButton.y + 6, wifiButton.width, wifiButton.height)
    }

    AppLauncherPopup {
        id: appLauncher

        targetWindow: bar

        anchorRect: Qt.rect(0, content.y + 6, bar.width, content.height)
    }

    ClipboardPopup {
        id: clipboardPopup
    
        capture: captureService
        store: clipboardModel
        targetWindow: bar
        anchorRect: Qt.rect(content.x + clipboardChip.x, content.y + clipboardChip.y + 6, clipboardChip.width, clipboardChip.height)
    }

    CapturePopup {
        id: recordPopup

        kind: "record"
        capture: captureService
        targetWindow: bar
        anchorRect: Qt.rect(content.x + recordChip.x, content.y + recordChip.y + 6, recordChip.width, recordChip.height)
    }

    ControlsPopup {
        id: controlsPopup

        capture: captureService
        targetWindow: bar
        anchorRect: Qt.rect(content.x + controlsButton.x, content.y + controlsButton.y + 6, controlsButton.width, controlsButton.height)
    }

    TrayPopup {
        id: trayPopup
    
        targetWindow: bar
        trayItem: bar.selectedTrayItem
    }

    IpcHandler {
        target: "bar"

        function toggleLauncher(): void {
            appLauncher.toggle();
        }

        function toggleControls(): void {
            controlsPopup.toggle();
        }

        function toggleWifi(): void {
            wifiPopup.toggle();
        }

        function screenshot(): void {
            captureService.startCapture("shot");
        }

        function toggleRecording(): void {
            if (captureService.recording)
                captureService.stopRecording();
            else
                captureService.startCapture("record");
        }

        function toggleClipboard(): void {
            if (clipboardModel.count > 0)
                clipboardPopup.toggle();
        }
        
        function toggleRecordingPopup(): void {
            if (captureService.recording)
                recordPopup.toggle();
        }
        
        function closeAll(): void {
            appLauncher.isOpen = false;
            controlsPopup.isOpen = false;
            wifiPopup.isOpen = false;
            clipboardPopup.isOpen = false;
            recordPopup.isOpen = false;
	    trayPopup.isOpen = false;
        }
    }
}
