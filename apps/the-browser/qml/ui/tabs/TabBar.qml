import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Ciel.Ui
import Ciel.Browser 1.0
import "../profilePage/"

Item {
    id: root

    property WorkspaceModel workspaceModel: null
    property var getWorkspaceViews: null
    property BrowserConfig config: null
    property var browserSettings: null
    property var activeView: null
    property bool collapsed: false
    property real tabHeight: 36
    property real pinnedSectionHeight: 0.0
    property var webProfile: null

    property int dragSourceIndex: -1
    property int dragTargetIndex: -1
    property int unpinningIndex: -1
    property bool dragOverPinZone: false
    property bool pinDropCommitted: false
    property bool isPrivate: false

    property int currentPinnedCount: 0
    property real currentPinSlotWidth: width - 16

    function getPinDropTarget(sourceItem) {
        var currentPane = pinnedWsRepeater ? pinnedWsRepeater.itemAt(workspaceModel ? workspaceModel.currentIndex : 0) : null;
        if (currentPane) {
            var ph = currentPane.placeholderItem;
            if (ph && ph.visible) {
                var pos = ph.mapToItem(root, 0, 0);
                return Qt.rect(pos.x, pos.y, ph.width, ph.height);
            }
            var slot = currentPane.effectivePinnedCount;
            var total = Math.min(6, slot + 1);
            var tileW = currentPane.getTileWidth(slot, total);
            var tileX = currentPane.getTileX(slot, total) + 8;
            var tileY = pinnedSectionContainer.y + 4 + currentPane.getTileY(slot, total);
            return Qt.rect(tileX, tileY, tileW, 36);
        }
        return Qt.rect(8, separatorY - 40, currentPinSlotWidth, 36);
    }

    property real animatedWorkspaceIndex: root.workspaceModel ? root.workspaceModel.currentIndex : 0.0

    Behavior on animatedWorkspaceIndex {
        CielSpring {
            damping: 0.35
            spring: 3.6
            mass: 0.95
            epsilon: 0.001
        }
    }

    property alias downloadsPopup: downloadsPopup
    property alias tabListContainer: tabListContainer
    readonly property real separatorY: separatorLine.y

    signal tabCollisionImpulse(int sourceIndex)
    signal historyRequested
    signal newTabRequested
    signal newWindowRequested
    signal newPrivateWindowRequested
    signal restoreTabRequested
    signal downloadsRequested
    signal passwordsRequested
    signal bookmarksRequested
    signal printRequested
    signal savePageRequested
    signal translateRequested
    signal findInPageRequested
    signal settingsRequested
    signal profilesRequested
    signal extensionsRequested
    signal sitePermissionsRequested

    readonly property real collapsedWidth: 56
    readonly property real expandedWidth: 200
    readonly property real targetWidth: collapsed ? collapsedWidth : expandedWidth

    implicitWidth: targetWidth
    implicitHeight: parent.height

    property real horizontalScrollAccumulator: 0.0
    property bool horizontalGestureTriggered: false

    Timer {
        id: horizontalGestureEndTimer

        interval: 180

        onTriggered: {
            root.horizontalScrollAccumulator = 0;
            root.horizontalGestureTriggered = false;
        }
    }

    WheelHandler {
        id: horizontalWheelHandler

        target: null
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        onWheel: event => {
            if (!root.workspaceModel)
                return;
            var dx = event.pixelDelta.x;

            if (dx === 0)
                dx = event.angleDelta.x;

            if (dx === 0)
                return;
            event.accepted = true;

            horizontalGestureEndTimer.restart();

            if (root.horizontalGestureTriggered)
                return;
            root.horizontalScrollAccumulator += dx;

            var threshold = event.pixelDelta.x !== 0 ? 45 : 60;

            if (Math.abs(root.horizontalScrollAccumulator) < threshold)
                return;
            root.horizontalGestureTriggered = true;

            var direction = root.horizontalScrollAccumulator < 0 ? 1 : -1;

            root.horizontalScrollAccumulator = 0;

            var nextIndex = root.workspaceModel.currentIndex + direction;

            if (nextIndex >= 0 && nextIndex < root.workspaceModel.count) {
                root.workspaceModel.currentIndex = nextIndex;
            }
        }
    }

    Behavior on implicitWidth {
        CielSpring {
            damping: 3.0
            spring: 10.2
            mass: 3.2
            epsilon: 0.002
        }
    }

    CielSquircle {
        anchors.fill: parent
        color: Theme.background
        borderWidth: 0
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TabHeaderVertical {
            id: tabHeaderItem
            Layout.fillWidth: true
            z: 10
            collapsed: root.collapsed
            activeView: root.activeView
            config: root.config
            browserSettings: root.browserSettings
            onCollapseToggled: root.collapsed = !root.collapsed
	    webProfile: root.webProfile
            isPrivate: root.isPrivate
            onSitePermissionsRequested: root.sitePermissionsRequested()
        }

        Item {
            id: pinnedSectionContainer
            Layout.fillWidth: true
            Layout.preferredHeight: root.collapsed ? 0 : root.pinnedSectionHeight
            visible: !root.collapsed && (Layout.preferredHeight > 0.01 || root.dragSourceIndex !== -1 || root.unpinningIndex !== -1)
            clip: true
            z: 12

            Rectangle {
                anchors.fill: parent
                color: Theme.background
                z: -1
            }

            Behavior on Layout.preferredHeight {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            Item {
                id: pinnedAreaDeck
                anchors.fill: parent

                Repeater {
                    id: pinnedWsRepeater
                    model: root.workspaceModel

                    Item {
                        id: wsPinnedPane
                        anchors.fill: parent

                        readonly property int wsIndex: index
                        readonly property bool isCurrentWorkspace: root.workspaceModel && root.workspaceModel.currentIndex === wsIndex
                        readonly property var wsTabModel: root.workspaceModel ? root.workspaceModel.tabModel(model.id) : null
                        readonly property var wsViews: root.getWorkspaceViews ? root.getWorkspaceViews(wsIndex) : null
                        readonly property real diff: wsIndex - root.animatedWorkspaceIndex

                        property int pinnedCount: 0
                        readonly property var placeholderItem: pinDropPlaceholderItem

                        function recalcPinnedCount() {
                            var count = 0;
                            if (wsTabModel) {
                                for (var i = 0; i < wsTabModel.count; ++i) {
                                    var val = wsTabModel.data(wsTabModel.index(i, 0), 264);
                                    if (val === true || val === 1) {
                                        count++;
                                    }
                                }
                            }
                            pinnedCount = count;
                        }

                        Component.onCompleted: recalcPinnedCount()
                        onWsTabModelChanged: recalcPinnedCount()

                        Connections {
                            target: wsPinnedPane.wsTabModel
                            function onDataChanged() {
                                wsPinnedPane.recalcPinnedCount();
                            }
                            function onRowsInserted() {
                                wsPinnedPane.recalcPinnedCount();
                            }
                            function onRowsRemoved() {
                                wsPinnedPane.recalcPinnedCount();
                            }
                            function onRowsMoved() {
                                wsPinnedPane.recalcPinnedCount();
                            }
                            function onModelReset() {
                                wsPinnedPane.recalcPinnedCount();
                            }
                        }

                        readonly property int activeUnpinCount: (root.unpinningIndex !== -1 && isCurrentWorkspace) ? 1 : 0
                        readonly property int effectivePinnedCount: Math.max(0, pinnedCount - activeUnpinCount)
                        readonly property int totalVisibleTiles: Math.min(6, effectivePinnedCount + (root.dragOverPinZone ? 1 : 0))
                        readonly property int pinRows: totalVisibleTiles <= 3 ? (totalVisibleTiles > 0 ? 1 : 0) : 2
                        readonly property real paneHeight: totalVisibleTiles > 0 ? ((pinRows * 36) + ((pinRows - 1) * 6) + 8) : 0

                        function getTileSlotIndex(tabIndex) {
                            if (root.unpinningIndex !== -1 && tabIndex > root.unpinningIndex) {
                                return tabIndex - 1;
                            }
                            return tabIndex;
                        }

                        function getTileWidth(slotIdx, total) {
                            var w = (pinnedGrid && pinnedGrid.width > 0) ? pinnedGrid.width : (root.width - 16);
                            if (total <= 1) {
                                return w;
                            }
                            var r1Count = Math.min(3, total);
                            var r2Count = total > 3 ? (total - 3) : 0;
                            var itemsInThisRow = (slotIdx < 3) ? r1Count : r2Count;

                            if (itemsInThisRow === 1) {
                                return w;
                            } else if (itemsInThisRow === 2) {
                                return Math.max(0, Math.floor((w - 6) / 2));
                            } else {
                                return Math.max(0, Math.floor((w - 12) / 3));
                            }
                        }

                        function getTileX(slotIdx, total) {
                            var row = slotIdx < 3 ? 0 : 1;
                            var col = slotIdx < 3 ? slotIdx : (slotIdx - 3);
                            var tileW = getTileWidth(slotIdx, total);
                            return col * (tileW + 6);
                        }

                        function getTileY(slotIdx, total) {
                            var row = slotIdx < 3 ? 0 : 1;
                            return row * (36 + 6);
                        }

                        Binding {
                            target: root
                            property: "pinnedSectionHeight"
                            value: wsPinnedPane.paneHeight
                            when: wsPinnedPane.isCurrentWorkspace
                        }

                        Binding {
                            target: root
                            property: "currentPinnedCount"
                            value: wsPinnedPane.pinnedCount
                            when: wsPinnedPane.isCurrentWorkspace
                        }

                        Binding {
                            target: root
                            property: "currentPinSlotWidth"
                            value: wsPinnedPane.getTileWidth(wsPinnedPane.effectivePinnedCount, wsPinnedPane.totalVisibleTiles)
                            when: wsPinnedPane.isCurrentWorkspace
                        }

                        visible: Math.abs(diff) < 0.99
                        enabled: Math.abs(diff) < 0.08
                        z: isCurrentWorkspace ? 10 : 1

                        Item {
                            id: pinnedGrid
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.topMargin: 4
                            height: wsPinnedPane.paneHeight

                            Repeater {
                                id: pinRepeater
                                model: wsPinnedPane.wsTabModel

                                Item {
                                    id: pinnedTile
                                    readonly property bool isPinned: Boolean(model.isPinned)
                                    readonly property bool isTemporarilyOut: root.unpinningIndex === index
                                    readonly property int slotIdx: wsPinnedPane.getTileSlotIndex(index)

                                    property real startTileW: 52

                                    x: wsPinnedPane.getTileX(slotIdx, wsPinnedPane.totalVisibleTiles)
                                    y: wsPinnedPane.getTileY(slotIdx, wsPinnedPane.totalVisibleTiles)
                                    width: (isPinned && !isTemporarilyOut) ? wsPinnedPane.getTileWidth(slotIdx, wsPinnedPane.totalVisibleTiles) : 0
                                    height: (isPinned && !isTemporarilyOut) ? 36 : 0
                                    visible: isPinned && index < 6

                                    Behavior on x {
                                        NumberAnimation {
                                            duration: 160
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Behavior on y {
                                        NumberAnimation {
                                            duration: 160
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Behavior on width {
                                        enabled: !root.pinDropCommitted
                                        NumberAnimation {
                                            duration: 160
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 160
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    readonly property bool isCurrent: wsPinnedPane.wsTabModel ? wsPinnedPane.wsTabModel.currentIndex === index : false
                                    readonly property bool isHovered: tileMouse.containsMouse

                                    property bool isDragging: false
                                    property bool isLanding: false
                                    property real dragX: 0.0
                                    property real dragY: 0.0
                                    property real landX: 0.0
                                    property real landY: 0.0
                                    property real unpinMorphProgress: 0.0

                                    Behavior on unpinMorphProgress {
                                        CielSpring {
                                            damping: 0.32
                                            spring: 6.5
                                            mass: 0.8
                                            epsilon: 0.001
                                        }
                                    }

                                    CielSpring {
                                        id: pinReturnSpringX
                                        target: pinnedTile
                                        property: "landX"
                                        damping: 0.34
                                        spring: 5.4
                                        mass: 1.0
                                        epsilon: 0.001
                                    }

                                    CielSpring {
                                        id: pinReturnSpringY
                                        target: pinnedTile
                                        property: "landY"
                                        damping: 0.34
                                        spring: 5.4
                                        mass: 1.0
                                        epsilon: 0.001
                                        onFinished: {
                                            Qt.callLater(function () {
                                                pinnedTile.isLanding = false;
                                                pinnedTile.dragX = 0;
                                                pinnedTile.dragY = 0;
                                                pinnedTile.landX = 0;
                                                pinnedTile.landY = 0;
                                            });
                                        }
                                    }

                                    CielSpring {
                                        id: pinToNormalSpringX
                                        target: pinnedTile
                                        property: "landX"
                                        damping: 0.34
                                        spring: 5.4
                                        mass: 1.0
                                        epsilon: 0.001
                                    }

                                    CielSpring {
                                        id: pinToNormalSpringY
                                        target: pinnedTile
                                        property: "landY"
                                        damping: 0.34
                                        spring: 5.4
                                        mass: 1.0
                                        epsilon: 0.001

                                        property int targetSlot: -1

                                        onFinished: {
                                            var slot = targetSlot;
                                            targetSlot = -1;

                                            root.dragSourceIndex = -1;
                                            root.dragTargetIndex = -1;
                                            root.unpinningIndex = -1;

                                            wsPinnedPane.wsTabModel.setPinned(index, false);
                                            if (slot !== -1 && slot !== index) {
                                                wsPinnedPane.wsTabModel.moveTab(index, slot);
                                            }

                                            Qt.callLater(function () {
                                                pinnedTile.isLanding = false;
                                                pinnedTile.dragX = 0;
                                                pinnedTile.dragY = 0;
                                                pinnedTile.landX = 0;
                                                pinnedTile.landY = 0;
                                                pinnedTile.unpinMorphProgress = 0;
                                            });
                                        }
                                    }

                                    Item {
                                        id: tileVisual
                                        parent: (pinnedTile.isDragging || pinnedTile.isLanding) ? root : pinnedTile
                                        z: (pinnedTile.isDragging || pinnedTile.isLanding) ? 1000 : 1

                                        readonly property real targetW: root.width - 16
                                        readonly property real morphP: pinnedTile.unpinMorphProgress
                                        width: (pinnedTile.isDragging || pinnedTile.isLanding) ? (pinnedTile.startTileW + (targetW - pinnedTile.startTileW) * morphP) : parent.width
                                        height: 36

                                        x: {
                                            if (pinnedTile.isLanding)
                                                return pinnedTile.landX;
                                            if (pinnedTile.isDragging)
                                                return pinnedTile.dragX;
                                            return 0;
                                        }

                                        y: {
                                            if (pinnedTile.isLanding)
                                                return pinnedTile.landY;
                                            if (pinnedTile.isDragging)
                                                return pinnedTile.dragY;
                                            return 0;
                                        }

                                        CielSquircle {
                                            anchors.fill: parent
                                            color: Theme.surface
                                            borderWidth: 1
                                            borderColor: Theme.border
                                            opacity: (pinnedTile.isCurrent || pinnedTile.isDragging || pinnedTile.isLanding) ? 1.0 : (pinnedTile.isHovered ? 0.75 : 0.0)

                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: 120
                                                    easing.type: Easing.OutQuad
                                                }
                                            }
                                        }

                                        Item {
                                            id: pinFaviconWrap
                                            width: 40
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            x: ((tileVisual.width - width) / 2) * (1.0 - tileVisual.morphP)

                                            Image {
                                                id: pinFavicon
                                                anchors.centerIn: parent
                                                width: 18
                                                height: 18
                                                sourceSize.width: 36
                                                sourceSize.height: 36
                                                fillMode: Image.PreserveAspectFit
                                                source: {
                                                    var v = (wsPinnedPane.wsViews && wsPinnedPane.wsViews.itemAt) ? wsPinnedPane.wsViews.itemAt(index) : null;
                                                    return (v && v.engine && v.engine.icon) ? v.engine.icon : "";
                                                }
                                                visible: status === Image.Ready
                                            }

                                            CielIcon {
                                                anchors.centerIn: parent
                                                icon: "globe"
                                                size: Theme.XSMALL
                                                color: pinnedTile.isCurrent ? Theme.textPrimary : Theme.textSecondary
                                                visible: !pinFavicon.visible
                                            }
                                        }

                                        Text {
                                            x: 44
                                            width: Math.max(0, tileVisual.targetW - 52)
                                            anchors.verticalCenter: parent.verticalCenter
                                            clip: true
                                            opacity: Math.max(0.0, (tileVisual.morphP - 0.25) / 0.75)
                                            visible: opacity > 0.01
                                            text: model.title ? model.title : "New Tab"
                                            font.pixelSize: 12
                                            font.weight: pinnedTile.isCurrent ? Font.Medium : Font.Normal
                                            color: pinnedTile.isCurrent ? Theme.textPrimary : Theme.textSecondary
                                            elide: Text.ElideRight
                                        }

                                        MouseArea {
                                            id: tileMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: pinnedTile.isDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton

                                            property bool dragStarted: false
                                            property real startClickX: 0.0
                                            property real startClickY: 0.0

                                            onPressed: mouse => {
                                                if (mouse.button === Qt.LeftButton) {
                                                    dragStarted = false;
                                                    startClickX = mouse.x;
                                                    startClickY = mouse.y;
                                                    pinnedTile.startTileW = pinnedTile.width;
                                                }
                                            }

                                            onPositionChanged: mouse => {
                                                if (!pressed || !isPinned)
                                                    return;

                                                var m = tileMouse.mapToItem(root, mouse.x, mouse.y);
                                                var curHubX = m.x;
                                                var curHubY = m.y;

                                                if (!dragStarted) {
                                                    var deltaX = mouse.x - startClickX;
                                                    var deltaY = mouse.y - startClickY;
                                                    if ((deltaX * deltaX + deltaY * deltaY) > 25) {
                                                        dragStarted = true;
                                                        pinnedTile.isDragging = true;
                                                        root.dragSourceIndex = index;
                                                    }
                                                }

                                                if (pinnedTile.isDragging) {
                                                    var inNormalArea = (tileVisual.morphP > 0.5) ? (curHubY > root.separatorY - 8) : (curHubY > root.separatorY + 16);

                                                    pinnedTile.unpinMorphProgress = inNormalArea ? 1.0 : 0.0;

                                                    var nextUnpinIdx = inNormalArea ? index : -1;
                                                    if (root.unpinningIndex !== nextUnpinIdx) {
                                                        root.unpinningIndex = nextUnpinIdx;
                                                    }

                                                    pinnedTile.dragX = curHubX - (tileVisual.width / 2);
                                                    pinnedTile.dragY = curHubY - startClickY;

                                                    if (inNormalArea) {
                                                        var normalCount = wsPinnedPane.wsTabModel.count - wsPinnedPane.pinnedCount;
                                                        var relY = curHubY - (tabListContainer.y + 6);
                                                        var rawSlot = Math.floor(relY / (root.tabHeight + 4));
                                                        var normalSlot = Math.max(0, Math.min(normalCount, rawSlot));
                                                        root.dragTargetIndex = normalSlot;
                                                    } else {
                                                        root.dragTargetIndex = -1;
                                                    }
                                                }
                                            }

                                            onReleased: mouse => {
                                                if (mouse.button === Qt.RightButton && !pinnedTile.isDragging) {
                                                    if (wsPinnedPane.wsTabModel)
                                                        wsPinnedPane.wsTabModel.setPinned(index, false);
                                                    return;
                                                }

                                                if (!dragStarted) {
                                                    if (wsPinnedPane.wsTabModel)
                                                        wsPinnedPane.wsTabModel.currentIndex = index;
                                                    return;
                                                }

                                                if (pinnedTile.isDragging) {
                                                    var m = tileMouse.mapToItem(root, mouse.x, mouse.y);
                                                    var curHubY = m.y;
                                                    var droppedInNormal = curHubY > (root.separatorY + 6);

                                                    if (droppedInNormal) {
                                                        var normalCount = wsPinnedPane.wsTabModel.count - wsPinnedPane.pinnedCount;
                                                        var normalSlot = root.dragTargetIndex !== -1 ? root.dragTargetIndex : normalCount;
                                                        var targetY = tabListContainer.y + (normalSlot * (root.tabHeight + 4)) + 6;
                                                        var targetX = 8;
                                                        var targetModelSlot = (wsPinnedPane.pinnedCount - 1) + normalSlot;

                                                        pinnedTile.landX = tileVisual.x;
                                                        pinnedTile.landY = tileVisual.y;
                                                        pinnedTile.isLanding = true;
                                                        pinnedTile.isDragging = false;

                                                        pinToNormalSpringX.stop();
                                                        pinToNormalSpringX.from = tileVisual.x;
                                                        pinToNormalSpringX.to = targetX;
                                                        pinToNormalSpringX.restart();

                                                        pinToNormalSpringY.stop();
                                                        pinToNormalSpringY.from = tileVisual.y;
                                                        pinToNormalSpringY.to = targetY;
                                                        pinToNormalSpringY.targetSlot = targetModelSlot;
                                                        pinToNormalSpringY.restart();

                                                        return;
                                                    }

                                                    var restingPos = pinnedTile.mapToItem(root, 0, 0);

                                                    root.dragSourceIndex = -1;
                                                    root.dragTargetIndex = -1;
                                                    root.unpinningIndex = -1;

                                                    pinnedTile.landX = tileVisual.x;
                                                    pinnedTile.landY = tileVisual.y;
                                                    pinnedTile.isLanding = true;
                                                    pinnedTile.isDragging = false;
                                                    pinnedTile.unpinMorphProgress = 0.0;

                                                    pinReturnSpringX.stop();
                                                    pinReturnSpringX.from = tileVisual.x;
                                                    pinReturnSpringX.to = restingPos.x;
                                                    pinReturnSpringX.restart();

                                                    pinReturnSpringY.stop();
                                                    pinReturnSpringY.from = tileVisual.y;
                                                    pinReturnSpringY.to = restingPos.y;
                                                    pinReturnSpringY.restart();
                                                }
                                            }

                                            onCanceled: {
                                                if (pinnedTile.isDragging) {
                                                    pinnedTile.isDragging = false;
                                                    pinnedTile.isLanding = false;
                                                    pinnedTile.unpinMorphProgress = 0;
                                                    root.dragSourceIndex = -1;
                                                    root.dragTargetIndex = -1;
                                                    root.unpinningIndex = -1;
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                id: pinDropPlaceholderItem
                                x: wsPinnedPane.getTileX(wsPinnedPane.effectivePinnedCount, wsPinnedPane.totalVisibleTiles)
                                y: wsPinnedPane.getTileY(wsPinnedPane.effectivePinnedCount, wsPinnedPane.totalVisibleTiles)
                                width: wsPinnedPane.getTileWidth(wsPinnedPane.effectivePinnedCount, wsPinnedPane.totalVisibleTiles)
                                height: 36
                                visible: root.dragOverPinZone && wsPinnedPane.totalVisibleTiles <= 6

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 160
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on y {
                                    NumberAnimation {
                                        duration: 160
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 160
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                CielSquircle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    borderWidth: 1
                                    borderColor: Theme.accent
                                    opacity: (!root.pinDropCommitted && root.dragOverPinZone) ? 0.65 : 0.0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 120
                                            easing.type: Easing.OutQuad
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: separatorLine
            Layout.fillWidth: true
            height: 1
            color: Theme.border
            z: 8
        }

        Item {
            id: tabListContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            z: root.dragSourceIndex !== -1 ? 999 : 1
            clip: false

            Repeater {
                model: root.workspaceModel

                Item {
                    id: wsVerticalPane
                    anchors.fill: parent

                    readonly property int wsIndex: index
                    readonly property bool isTarget: root.workspaceModel && root.workspaceModel.currentIndex === wsIndex
                    readonly property var wsTabModel: root.workspaceModel ? root.workspaceModel.tabModel(model.id) : null
                    readonly property var wsViews: root.getWorkspaceViews ? root.getWorkspaceViews(wsIndex) : null
                    readonly property real diff: wsIndex - root.animatedWorkspaceIndex

                    visible: Math.abs(diff) < 0.99
                    enabled: Math.abs(diff) < 0.08
                    z: isTarget ? 10 : 1

                    Flickable {
                        id: tabFlickVertical
                        anchors.fill: parent
                        contentHeight: tabColumnVertical.height
                        contentWidth: width
                        clip: false
                        interactive: root.dragSourceIndex === -1
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: tabColumnVertical
                            width: parent.width
                            spacing: 4
                            topPadding: 6
                            bottomPadding: 6

                            Repeater {
                                id: verticalTabRepeater
                                model: wsVerticalPane.wsTabModel

                                delegate: TabDelegateVertical {
                                    width: tabColumnVertical.width
                                    tabModel: wsVerticalPane.wsTabModel
                                    tabRepeater: verticalTabRepeater
                                    views: wsVerticalPane.wsViews
                                    collisionHub: root
                                    collapsed: root.collapsed
                                    tabHeight: root.tabHeight
                                    workspaceDiff: wsVerticalPane.diff
                                    isTargetWorkspace: wsVerticalPane.isTarget
                                }
                            }

                            Item {
                                id: plusBtnWrap
                                width: tabColumnVertical.width
                                height: 36

                                readonly property int tabCount: wsVerticalPane.wsTabModel ? wsVerticalPane.wsTabModel.count : 0
                                readonly property real stagger: wsVerticalPane.isTarget ? 0.0 : (tabCount * 0.05)
                                readonly property real absDiff: Math.abs(wsVerticalPane.diff)
                                readonly property real btnP: Math.max(0.0, Math.min(1.0, (absDiff - stagger) / 0.55))
                                readonly property real dir: wsVerticalPane.diff >= 0 ? 1 : -1

                                readonly property real slotSpan: root.tabHeight + 4
                                readonly property real targetShiftY: {
                                    if (root.dragOverPinZone && root.dragSourceIndex !== -1) {
                                        return -slotSpan;
                                    }
                                    if (root.unpinningIndex !== -1 && root.dragTargetIndex !== -1) {
                                        return slotSpan;
                                    }
                                    return 0.0;
                                }

                                property real animatedShiftY: targetShiftY

                                Behavior on animatedShiftY {
                                    enabled: (root.dragSourceIndex !== -1 || root.unpinningIndex !== -1)
                                    CielSpring {
                                        damping: 0.32
                                        spring: 5.2
                                        mass: 1.0
                                        epsilon: 0.001
                                    }
                                }

                                transform: [
                                    Translate {
                                        x: Math.round(plusBtnWrap.dir * plusBtnWrap.btnP * (tabColumnVertical.width + 16))
                                        y: plusBtnWrap.animatedShiftY
                                    }
                                ]
                                opacity: Math.max(0.0, 1.0 - plusBtnWrap.btnP * 1.5)

                                CielIconButton {
                                    anchors.centerIn: parent
                                    icon: "plus"
                                    size: Theme.XSMALL
                                    onClicked: root.newTabRequested()
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: sidebarFooter
            Layout.fillWidth: true
            Layout.preferredHeight: root.collapsed ? (btnSize * numberOfButtonsWhenCollapsed + margin * 2) : (btnSize * numberOfButtonsWhenExpanded + margin * 2 + 14)
            z: 25
            clip: true

            property real collapseProgress: root.collapsed ? 1.0 : 0.0

            readonly property real btnSize: 36
            readonly property real margin: 8

            readonly property int numberOfButtonsWhenCollapsed: 3
            readonly property int numberOfButtonsWhenExpanded: 2

            Behavior on Layout.preferredHeight {
                CielSpring {
                    damping: 3.0
                    spring: 10.2
                    mass: 3.2
                    epsilon: 0.002
                }
            }
            Behavior on collapseProgress {
                CielSpring {
                    damping: 3.0
                    spring: 10.2
                    mass: 3.2
                    epsilon: 0.002
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.background
                z: -1
            }

            Item {
                id: profileTrigger
                width: sidebarFooter.btnSize
                height: sidebarFooter.btnSize

                readonly property real expX: sidebarFooter.margin
                readonly property real expY: Math.round(sidebarFooter.height - height - sidebarFooter.margin) - sidebarFooter.btnSize
                readonly property real colX: Math.round((sidebarFooter.width - width) / 2)
                readonly property real colY: sidebarFooter.margin

                x: Math.round(expX + (colX - expX) * sidebarFooter.collapseProgress)
                y: Math.round(expY + (colY - expY) * sidebarFooter.collapseProgress)

                property var profiles: ProfileManager.listProfiles()
                readonly property bool hasExtraProfiles: profiles.length > 1

                Connections {
                    target: ProfileManager
                    function onActiveProfileChanged() {
                        profileTrigger.profiles = ProfileManager.listProfiles();
                    }
                }

                CielIconButton {
                    id: addProfileBtn
                    anchors.fill: parent
                    size: Theme.SMALL
                    icon: "user"
                    visible: !profileTrigger.hasExtraProfiles
                    onClicked: root.profilesRequested()
                }

                Item {
                    id: avatarStack
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: sidebarFooter.btnSize
                    height: sidebarFooter.btnSize
                    visible: profileTrigger.hasExtraProfiles
                    clip: false

                    property var heldIds: []

                    readonly property var shown: {
                        var list = profileTrigger.profiles || [];
                        var map = ({});
                        for (var i = 0; i < list.length; ++i)
                            map[list[i].id] = list[i];
                        var out = [];
                        for (var i = 0; i < heldIds.length; ++i) {
                            if (map[heldIds[i]])
                                out.push(map[heldIds[i]]);
                        }
                        return out;
                    }

                    readonly property int stackCount: shown.length
                    property int foldedCount: 0
                    property bool folding: false
                    property real bounceScale: 1.0

                    function ensureSlotIds() {
                        var list = profileTrigger.profiles || [];
                        var byId = ({});
                        var activeId = "";
                        for (var i = 0; i < list.length; ++i) {
                            byId[list[i].id] = list[i];
                            if (list[i].isActive)
                                activeId = list[i].id;
                        }

                        var ids = [];
                        for (var i = 0; i < heldIds.length; ++i) {
                            if (byId[heldIds[i]])
                                ids.push(heldIds[i]);
                        }
                        if (activeId && ids.indexOf(activeId) < 0) {
                            if (ids.length < 3)
                                ids.push(activeId);
                            else
                                ids[ids.length - 1] = activeId;
                        }
                        for (var i = 0; i < list.length && ids.length < 3; ++i) {
                            if (ids.indexOf(list[i].id) < 0)
                                ids.push(list[i].id);
                        }
                        var same = ids.length === heldIds.length;
                        if (same) {
                            for (var i = 0; i < ids.length; ++i) {
                                if (ids[i] !== heldIds[i])
                                    same = false;
                            }
                        }
                        if (!same)
                            heldIds = ids;
                    }

                    function syncAllSlots() {
                        for (var i = 0; i < stackRepeater.count; ++i) {
                            var it = stackRepeater.itemAt(i);
                            if (it && it.syncSlot)
                                it.syncSlot();
                        }
                    }

                    function sizeAt(fromBottom) {
                        return 22 + Math.max(0, stackCount - 1 - fromBottom) * 4;
                    }
                    function restY(fromBottom) {
                        return (height - sizeAt(0)) - fromBottom * 8;
                    }
                    function coverY(fromBottom) {
                        return (height - sizeAt(0)) + (sizeAt(0) - sizeAt(fromBottom)) / 2;
                    }

                    function punchBounce() {
                        bounceScale = 1.18;
                        bounceReset.restart();
                    }

                    function expand() {
                        foldTimer.stop();
                        openTimer.stop();
                        bounceReset.stop();
                        if (foldedCount <= 0) {
                            folding = false;
                            bounceScale = 1.0;
                            return;
                        }
                        folding = true;
                        unfoldTimer.restart();
                    }

                    function playFold() {
                        if (folding || stackCount < 2)
                            return;
                        unfoldTimer.stop();
                        expandDelay.stop();
                        openTimer.stop();
                        folding = true;
                        foldedCount = 0;
                        foldTimer.restart();
                    }

                    Component.onCompleted: {
                        avatarStack.ensureSlotIds();
                        if (stackCount > 1) {
                            foldedCount = Math.max(0, stackCount - 1);
                            folding = true;
                            unfoldTimer.restart();
                        }
                        Qt.callLater(syncAllSlots);
                    }

                    Connections {
                        target: ProfileManager
                        function onActiveProfileChanged() {
                            profileTrigger.profiles = ProfileManager.listProfiles();
                            avatarStack.ensureSlotIds();
                            Qt.callLater(function () {
                                avatarStack.syncAllSlots();
                                avatarStack.punchBounce();
                            });
                        }
                        function onProfilesChanged() {
                            profileTrigger.profiles = ProfileManager.listProfiles();
                            avatarStack.ensureSlotIds();
                            Qt.callLater(avatarStack.syncAllSlots);
                        }
                    }

                    Behavior on bounceScale {
                        CielSpring {
                            damping: 1.0
                            spring: 20.2
                            mass: 3.2
                            epsilon: 0.002
                        }
                    }

                    Timer {
                        id: bounceReset
                        interval: 70
                        onTriggered: avatarStack.bounceScale = 1.0
                    }
                    Timer {
                        id: unfoldTimer
                        interval: 165
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: {
                            if (avatarStack.foldedCount > 0) {
                                if (avatarStack.foldedCount === avatarStack.stackCount - 1)
                                    avatarStack.punchBounce();
                                avatarStack.foldedCount--;
                            } else {
                                stop();
                                avatarStack.folding = false;
                            }
                        }
                    }
                    Timer {
                        id: foldTimer
                        interval: 165
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: {
                            if (avatarStack.foldedCount < avatarStack.stackCount - 1) {
                                if (avatarStack.foldedCount === 0)
                                    avatarStack.punchBounce();
                                avatarStack.foldedCount++;
                            } else {
                                stop();
                                openTimer.restart();
                            }
                        }
                    }
                    Timer {
                        id: openTimer
                        interval: 280
                        onTriggered: {
                            root.profilesRequested();
                            expandDelay.restart();
                        }
                    }
                    Timer {
                        id: expandDelay
                        interval: 650
                        onTriggered: avatarStack.expand()
                    }

                    Repeater {
                        id: stackRepeater
                        model: 3

                        Rectangle {
                            id: circle

                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#90000000"
                                shadowBlur: 0.5
                                shadowVerticalOffset: 0
                                shadowHorizontalOffset: 0
                            }

                            readonly property string profileId: index < avatarStack.heldIds.length ? avatarStack.heldIds[index] : ""
                            readonly property var currentData: {
                                var list = avatarStack.shown;
                                for (var i = 0; i < list.length; ++i) {
                                    if (list[i].id === profileId)
                                        return list[i];
                                }
                                return null;
                            }

                            visible: currentData !== null
                            property real stackSlot: 0

                            function syncSlot() {
                                if (!currentData) {
                                    stackSlot = 0;
                                    return;
                                }
                                if (currentData.isActive) {
                                    stackSlot = 0;
                                    return;
                                }
                                var rank = 1;
                                for (var i = 0; i < avatarStack.heldIds.length; ++i) {
                                    var d = null;
                                    for (var j = 0; j < avatarStack.shown.length; ++j) {
                                        if (avatarStack.shown[j].id === avatarStack.heldIds[i])
                                            d = avatarStack.shown[j];
                                    }
                                    if (!d || d.isActive)
                                        continue;
                                    if (d.id === currentData.id) {
                                        stackSlot = rank;
                                        return;
                                    }
                                    rank++;
                                }
                                stackSlot = rank;
                            }

                            readonly property bool isSelected: currentData ? currentData.isActive : false
                            readonly property bool folded: stackSlot > 0 && stackSlot >= (avatarStack.stackCount - avatarStack.foldedCount)

                            width: avatarStack.sizeAt(stackSlot)
                            height: avatarStack.sizeAt(stackSlot)
                            radius: width / 2
                            x: Math.round((avatarStack.width - width) / 2)
                            y: folded ? avatarStack.coverY(stackSlot) : avatarStack.restY(stackSlot)

                            z: Math.round((avatarStack.stackCount - stackSlot) * 10)

                            color: (currentData && currentData.color) ? currentData.color : Theme.surface
                            clip: true
                            scale: isSelected ? avatarStack.bounceScale : 1.0
                            transformOrigin: Item.Center

                            Behavior on stackSlot {
                                CielSpring {
                                    damping: 0.55
                                    spring: 14
                                    mass: 2.4
                                    epsilon: 0.002
                                }
                            }
                            Behavior on y {
                                CielSpring {
                                    damping: 0.55
                                    spring: 14
                                    mass: 2.4
                                    epsilon: 0.002
                                }
                            }
                            Behavior on width {
                                CielSpring {
                                    damping: 0.55
                                    spring: 14
                                    mass: 2.4
                                    epsilon: 0.002
                                }
                            }
                            Behavior on height {
                                CielSpring {
                                    damping: 0.55
                                    spring: 14
                                    mass: 2.4
                                    epsilon: 0.002
                                }
                            }

                            Component.onCompleted: syncSlot()

                            Image {
                                id: stackImg
                                anchors.fill: parent
                                source: circle.currentData ? circle.currentData.profileImage : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                                asynchronous: true
                            }

                            Rectangle {
                                id: stackMaskSource
                                anchors.fill: parent
                                anchors.margins: circle.border.width
                                radius: width / 2
                                visible: false
                                layer.enabled: true
                            }

                            MultiEffect {
                                anchors.fill: stackMaskSource
                                source: stackImg
                                maskEnabled: true
                                maskSource: stackMaskSource
                                visible: circle.currentData && circle.currentData.profileImage !== ""
                            }
                            Label {
                                anchors.centerIn: parent
                                text: (circle.currentData && circle.currentData.displayName) ? circle.currentData.displayName.charAt(0).toUpperCase() : ""
                                font.pixelSize: Math.max(9, circle.width * 0.4)
                                font.bold: true
                                color: "black"
                                visible: circle.currentData && circle.currentData.profileImage === ""
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !avatarStack.folding
                        onClicked: avatarStack.playFold()
                    }
                }
            }

            CielIconButton {
                id: settingsTrigger
                width: sidebarFooter.btnSize
                height: sidebarFooter.btnSize
                size: Theme.SMALL
                icon: "gear-six"

                readonly property real expX: sidebarFooter.margin
                readonly property real expY: Math.round(sidebarFooter.height - height - sidebarFooter.margin)
                readonly property real colX: Math.round((sidebarFooter.width - width) / 2)
                readonly property real colY: 80

                x: Math.round(expX + (colX - expX) * sidebarFooter.collapseProgress)
                y: Math.round(expY + (colY - expY) * sidebarFooter.collapseProgress)
            }

            Row {
                id: workspaceDots
                anchors.horizontalCenter: parent.horizontalCenter
                y: settingsTrigger.y + Math.round((settingsTrigger.height - height) / 2)
                spacing: 6
                opacity: 1.0 - sidebarFooter.collapseProgress
                visible: opacity > 0.01

                Repeater {
                    model: root.workspaceModel

                    Item {
                        id: dotWrapper
                        readonly property bool isActive: root.workspaceModel ? root.workspaceModel.currentIndex === index : false

                        readonly property color wsColor: model.color ? model.color : Theme.accent

                        width: isActive ? 18 : 6
                        height: 6

                        Behavior on width {
                            CielSpring {
                                damping: 0.32
                                spring: 5.2
                                mass: 1.0
                                epsilon: 0.001
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: dotWrapper.isActive ? dotWrapper.wsColor : Qt.alpha(dotWrapper.wsColor, 0.4)
                            scale: dotWrapper.isActive ? 1.0 : 0.85

                            Behavior on scale {
                                CielSpring {
                                    damping: 0.30
                                    spring: 5.4
                                    mass: 0.9
                                    epsilon: 0.001
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.workspaceModel)
                                    root.workspaceModel.currentIndex = index;
                            }
                        }
                    }
                }
            }

            CielIconButton {
                id: downloadsTrigger
                width: sidebarFooter.btnSize
                height: sidebarFooter.btnSize
                size: Theme.SMALL
                icon: "download-simple"

                readonly property real expX: Math.round(sidebarFooter.width - width - 8)
                readonly property real expY: Math.round(sidebarFooter.height - height - 8)
                readonly property real colX: Math.round((sidebarFooter.width - width) / 2)
                readonly property real colY: 44

                x: Math.round(expX + (colX - expX) * sidebarFooter.collapseProgress)
                y: Math.round(expY + (colY - expY) * sidebarFooter.collapseProgress)
            }

            BrowserSettingsMenu {
                id: settingsMenu
                trigger: settingsTrigger
                placement: root.collapsed ? "right" : "top"
                config: root.config
                workspaceModel: root.workspaceModel

                onHistoryRequested: root.historyRequested()
                onNewTabRequested: root.newTabRequested()
                onNewWindowRequested: root.newWindowRequested()
                onNewPrivateWindowRequested: root.newPrivateWindowRequested()
                onRestoreTabRequested: root.restoreTabRequested()
                onDownloadsRequested: root.downloadsRequested()
                onPasswordsRequested: root.passwordsRequested()
                onBookmarksRequested: root.bookmarksRequested()
                onPrintRequested: root.printRequested()
                onSavePageRequested: root.savePageRequested()
                onTranslateRequested: root.translateRequested()
                onFindInPageRequested: root.findInPageRequested()
                onSettingsRequested: root.settingsRequested()
                onExtensionsRequested: root.extensionsRequested()
                onSitePermissionsRequested: root.sitePermissionsRequested()
            }

            BrowserDownloadsPopup {
                id: downloadsPopup
                trigger: downloadsTrigger
                placement: root.isVertical ? "right" : "bottom"
                downloadsModel: root.config ? root.config.downloadsModel : null

                onPauseRequested: id => root.config.pauseDownload(id)
                onResumeRequested: id => root.config.resumeDownload(id)
                onCancelRequested: id => root.config.cancelDownload(id)
                onRetryRequested: id => root.config.retryDownload(id)
                onOpenFolderRequested: path => root.config.openFolder(path)
                onClearFinishedRequested: () => root.config.clearFinished()
            }
        }
    }
}
