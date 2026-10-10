import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ciel.Ui
import Ciel.Browser 1.0

Item {
    id: tabDelegateV

    required property int index
    required property string title
    required property string url
    required property bool loading
    required property bool isPinned
    required property TabModel tabModel

    property var views: null
    property var collisionHub: null
    property bool collapsed: false
    property real tabHeight: 36
    property real workspaceDiff: 0.0
    property bool isTargetWorkspace: false

    readonly property real slotSpan: tabHeight + 4
    readonly property int totalTabs: tabModel ? tabModel.count : 1

    property bool deferModelRemoval: false
property var tabRepeater: null
property var deferredCloseCallback: null

    readonly property int localPinnedCount: {
        if (collisionHub && collisionHub.currentPinnedCount > 0)
            return collisionHub.currentPinnedCount;
        if (!tabModel)
            return 0;
        var c = 0;
        for (var i = 0; i < tabModel.count; ++i) {
            var val = tabModel.data(tabModel.index(i, 0), 264);
            if (val === true || val === 1)
                c++;
            else
                break;
        }
        return c;
    }

    readonly property real staggerOffset: isTargetWorkspace ? ((totalTabs - 1 - index) * 0.05) : (index * 0.05)
    readonly property real absWsDiff: Math.abs(workspaceDiff)
    readonly property real wsP: Math.max(0.0, Math.min(1.0, (absWsDiff - staggerOffset) / 0.55))
    readonly property real wsDir: workspaceDiff >= 0 ? 1 : -1

    readonly property bool isCurrent: tabModel.currentIndex === tabDelegateV.index
    readonly property bool isHovered: tabHoverV.hovered
    readonly property var currentTabView: (views && views.itemAt) ? views.itemAt(tabDelegateV.index) : null
    readonly property url siteFavicon: {
        if (currentTabView && currentTabView.engine && currentTabView.engine.icon) {
            return currentTabView.engine.icon;
        }
        return "";
    }

    readonly property string displayTitle: {
        if (url.toString() === "ciel://history" || url.toString() === "about:history") {
            return "History";
        }
        if (title && title.length > 0 && title !== "about:blank" && !url.toString().startsWith("about:blank")) {
            return title;
        }
        return "New Tab";
    }

    property real spawnProgress: 0.0
    property real closeY: 0.0
    property real closeYScale: 1.0
    property real closeXScale: 1.0
    property real closeOpacity: 1.0
    property real closeDimension: 1.0
    property bool isClosing: false

    property real shockwaveOffset: 0.0

    property bool isDragging: false
    property real dragX: 0.0
    property real dragY: 0.0
    property real landX: 0.0
    property real landY: 0.0
    property bool isLanding: false

    readonly property real targetPinWidth: collisionHub ? collisionHub.currentPinSlotWidth : (tabDelegateV.width - 16)
    property real landingWidth: targetPinWidth

    property real pinMorphProgress: 0.0

    Behavior on pinMorphProgress {
        CielSpring {
            damping: 0.32
            spring: 6.5
            mass: 0.8
            epsilon: 0.001
        }
    }

    property real targetHubX: 0.0
    property real targetHubY: 0.0
    property real clickOffsetX: 0.0
    property real clickOffsetY: 0.0


function createTabBelow() {
    if (!tabModel)
        return;

    var insertIndex = tabDelegateV.index + 1;

    tabModel.addTab("about:blank");

    var newIndex = tabModel.count - 1;

    if (newIndex !== insertIndex)
        tabModel.moveTab(newIndex, insertIndex);

    tabModel.currentIndex = insertIndex;
}

function duplicateTab() {
    if (!tabModel)
        return;

    var sourceUrl = tabDelegateV.url;
    var insertIndex = tabDelegateV.index + 1;

    tabModel.addTab(sourceUrl || "about:blank");

    var newIndex = tabModel.count - 1;

    if (newIndex !== insertIndex)
        tabModel.moveTab(newIndex, insertIndex);

    tabModel.currentIndex = insertIndex;
}

function closeOtherTabs() {
    if (!tabModel || !tabRepeater)
        return;

    var keepIndex = tabDelegateV.index;
    var targets = [];

    for (var i = 0; i < tabModel.count; ++i) {
        if (i === keepIndex)
            continue;

        var delegate = tabRepeater.itemAt(i);
        if (delegate)
            targets.push(delegate);
    }

    if (targets.length === 0)
        return;

    var finishedCount = 0;
    var finalized = false;

    var onTargetFinished = function() {
        if (finalized)
            return;

        finishedCount++;

        if (finishedCount < targets.length)
            return;

        finalized = true;

        for (var j = 0; j < targets.length; ++j) {
            targets[j].deferredCloseCallback = null;
            targets[j].deferModelRemoval = false;
        }

        tabModel.closeOtherTabs(keepIndex);
    };

    for (var k = 0; k < targets.length; ++k) {
        targets[k].deferModelRemoval = true;
        targets[k].deferredCloseCallback = onTargetFinished;
    }

    for (var n = 0; n < targets.length; ++n) {
        targets[n].requestClose();
    }
}

function closeTabsToBottom() {
    if (!tabModel || !tabRepeater)
        return;

    var keepIndex = tabDelegateV.index;
    var targets = [];

    for (var i = keepIndex + 1; i < tabModel.count; ++i) {
        var delegate = tabRepeater.itemAt(i);
        if (delegate)
            targets.push(delegate);
    }

    if (targets.length === 0)
        return;

    var finishedCount = 0;
    var finalized = false;

    var onTargetFinished = function() {
        if (finalized)
            return;

        finishedCount++;

        if (finishedCount < targets.length)
            return;

        finalized = true;

        for (var j = 0; j < targets.length; ++j) {
            targets[j].deferredCloseCallback = null;
            targets[j].deferModelRemoval = false;
        }

        tabModel.closeTabsToBottom(keepIndex);
    };

    for (var k = 0; k < targets.length; ++k) {
        targets[k].deferModelRemoval = true;
        targets[k].deferredCloseCallback = onTargetFinished;
    }

    for (var n = 0; n < targets.length; ++n) {
        targets[n].requestClose();
    }
}

    function updateDragCoordinates() {
        if (!collisionHub || !isDragging)
            return;

        var baseW = Math.max(1.0, tabDelegateV.width - 16);
        var clickRatioX = Math.max(0.0, Math.min(1.0, clickOffsetX / baseW));
        var effectiveOffsetX = visualContentV.width * clickRatioX;

        tabDelegateV.dragX = targetHubX - effectiveOffsetX;
        tabDelegateV.dragY = targetHubY - clickOffsetY;
    }

    onPinMorphProgressChanged: {
        if (isDragging)
            updateDragCoordinates();
    }

    readonly property bool isDragSource: collisionHub && collisionHub.dragSourceIndex === tabDelegateV.index
    readonly property bool isUnpinningDrag: collisionHub && (collisionHub.unpinningIndex !== -1 || (collisionHub.dragSourceIndex !== -1 && collisionHub.dragSourceIndex < tabDelegateV.localPinnedCount))

    visible: !isPinned
    height: isPinned ? 0 : Math.max(0, tabHeight * spawnProgress * closeDimension)
    clip: false

    readonly property real targetShift: {
        if (!collisionHub || collisionHub.dragSourceIndex === -1 || isDragSource)
            return 0.0;

        var src = collisionHub.dragSourceIndex;
        var dst = collisionHub.dragTargetIndex;

        if (collisionHub.dragOverPinZone) {
            if (tabDelegateV.index > src)
                return -slotSpan;
            return 0.0;
        }

        if (dst === -1)
            return 0.0;

        if (isUnpinningDrag) {
            var myNormalSlot = tabDelegateV.index - tabDelegateV.localPinnedCount;
            if (myNormalSlot >= dst)
                return slotSpan;
            return 0.0;
        }

        if (src < dst) {
            if (tabDelegateV.index > src && tabDelegateV.index <= dst)
                return -slotSpan;
        } else if (src > dst) {
            if (tabDelegateV.index >= dst && tabDelegateV.index < src)
                return slotSpan;
        }
        return 0.0;
    }

    property real animatedShift: 0.0

    onIndexChanged: {
        shiftSpringV.stop();
        animatedShift = 0.0;
        if (isLanding) {
            isLanding = false;
            landX = 0.0;
            landY = 0.0;
            dragX = 0.0;
            dragY = 0.0;
        }
    }

    onTargetShiftChanged: {
        if (!isDragSource && !isClosing) {
            if (collisionHub && collisionHub.dragSourceIndex !== -1 && (collisionHub.dragTargetIndex !== -1 || collisionHub.dragOverPinZone)) {
                shiftSpringV.stop();
                shiftSpringV.to = targetShift;
                shiftSpringV.restart();
            } else {
                shiftSpringV.stop();
                animatedShift = 0.0;
            }
        }
    }

    CielSpring {
        id: shiftSpringV
        target: tabDelegateV
        property: "animatedShift"
        damping: 0.32
        spring: 5.2
        mass: 1.0
        epsilon: 0.001
    }

    CielSpring {
        id: normalLandSpringX
        target: tabDelegateV
        property: "landX"
        damping: 0.34
        spring: 5.4
        mass: 1.0
        epsilon: 0.001
    }

    CielSpring {
        id: normalLandSpringY
        target: tabDelegateV
        property: "landY"
        damping: 0.34
        spring: 5.4
        mass: 1.0
        epsilon: 0.001

        property int commitSrc: -1
        property int commitDst: -1

        onFinished: {
            var s = commitSrc;
            var d = commitDst;
            commitSrc = -1;
            commitDst = -1;

            if (s !== -1 && d !== -1 && s !== d) {
                tabModel.moveTab(s, d);
            }

            Qt.callLater(function () {
                tabDelegateV.isLanding = false;
                tabDelegateV.dragX = 0.0;
                tabDelegateV.dragY = 0.0;
                tabDelegateV.landX = 0.0;
                tabDelegateV.landY = 0.0;
                tabDelegateV.animatedShift = 0.0;
                tabDelegateV.pinMorphProgress = 0.0;

                if (collisionHub) {
                    collisionHub.dragSourceIndex = -1;
                    collisionHub.dragTargetIndex = -1;
                    collisionHub.dragOverPinZone = false;
                    collisionHub.pinDropCommitted = false;
                }
            });
        }
    }

    CielSpring {
        id: pinLandSpringX
        target: tabDelegateV
        property: "landX"
        damping: 0.34
        spring: 5.4
        mass: 1.0
        epsilon: 0.001
    }

    CielSpring {
        id: pinLandSpringY
        target: tabDelegateV
        property: "landY"
        damping: 0.34
        spring: 5.4
        mass: 1.0
        epsilon: 0.001

        onFinished: {
            tabModel.setPinned(tabDelegateV.index, true);

            if (collisionHub) {
                collisionHub.dragSourceIndex = -1;
                collisionHub.dragTargetIndex = -1;
                collisionHub.dragOverPinZone = false;
                collisionHub.pinDropCommitted = false;
            }

            Qt.callLater(function () {
                tabDelegateV.isLanding = false;
                tabDelegateV.dragX = 0.0;
                tabDelegateV.dragY = 0.0;
                tabDelegateV.landX = 0.0;
                tabDelegateV.landY = 0.0;
                tabDelegateV.pinMorphProgress = 0.0;
            });
        }
    }

    z: isDragSource ? 1000 : (isLanding ? 900 : 1)

    Behavior on shockwaveOffset {
        CielSpring {
            damping: 0.28
            spring: 5.2
            mass: 1.0
            epsilon: 0.001
        }
    }

    Connections {
        target: collisionHub
        function onTabCollisionImpulse(sourceIndex) {
            if (tabDelegateV.isClosing)
                return;
            var diff = sourceIndex - tabDelegateV.index;
            if (diff >= 1 && diff <= 3) {
                shockwaveTimerV.delayMs = (diff - 1) * 28;
                shockwaveTimerV.impulse = -13.5 * Math.pow(0.62, diff - 1);
                shockwaveTimerV.restart();
            }
        }
    }

    SequentialAnimation {
        id: shockwaveTimerV
        property int delayMs: 0
        property real impulse: 0.0

        PauseAnimation {
            duration: shockwaveTimerV.delayMs
        }
        ScriptAction {
            script: tabDelegateV.shockwaveOffset = shockwaveTimerV.impulse
        }
        PauseAnimation {
            duration: 115
        }
        ScriptAction {
            script: tabDelegateV.shockwaveOffset = 0.0
        }
    }

    function requestClose() {
        if (isClosing)
            return;
        isClosing = true;
        closeAnimationV.restart();
    }

    ParallelAnimation {
        id: closeAnimationV

        ScriptAction {
            script: if (collisionHub)
                collisionHub.tabCollisionImpulse(tabDelegateV.index)
        }

        NumberAnimation {
            target: tabDelegateV
            property: "closeY"
            from: 0.0
            to: -28.0
            duration: 190
            easing.type: Easing.OutCubic
        }

        SequentialAnimation {
            NumberAnimation {
                target: tabDelegateV
                property: "closeYScale"
                from: 1.0
                to: 0.32
                duration: 180
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: tabDelegateV
                property: "closeYScale"
                to: 0.0
                duration: 30
            }
        }

        SequentialAnimation {
            NumberAnimation {
                target: tabDelegateV
                property: "closeXScale"
                from: 1.0
                to: 1.08
                duration: 60
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: tabDelegateV
                property: "closeXScale"
                from: 1.08
                to: 0.20
                duration: 150
                easing.type: Easing.InQuad
            }
        }

        SequentialAnimation {
            PauseAnimation {
                duration: 45
            }
            NumberAnimation {
                target: tabDelegateV
                property: "closeDimension"
                from: 1.0
                to: 0.0
                duration: 175
                easing.type: Easing.InOutQuad
            }
        }

        SequentialAnimation {
            PauseAnimation {
                duration: 60
            }
            NumberAnimation {
                target: tabDelegateV
                property: "closeOpacity"
                from: 1.0
                to: 0.0
                duration: 145
                easing.type: Easing.OutQuad
            }
        }

onFinished: {
    if (tabDelegateV.deferModelRemoval) {
        if (tabDelegateV.deferredCloseCallback)
            tabDelegateV.deferredCloseCallback()
    } else {
        tabModel.closeTab(tabDelegateV.index)
    }
}
    }

    Component.onCompleted: spawnProgress = 1.0

    Behavior on spawnProgress {
        CielSpring {
            damping: 0.28
            spring: 4.8
            mass: 1.0
            epsilon: 0.002
        }
    }

    HoverHandler {
        id: tabHoverV
    }

    MouseArea {
        id: tabMouseV
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: tabDelegateV.isDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 0

        property bool dragThresholdMet: false

        onPressed: mouse => {
            if (mouse.button === Qt.LeftButton) {
                clickOffsetX = mouse.x;
                clickOffsetY = mouse.y;
                dragThresholdMet = false;

                if (collisionHub) {
                    var m = tabDelegateV.mapToItem(collisionHub, mouse.x, mouse.y);
                    targetHubX = m.x;
                    targetHubY = m.y;
                }

                if (!tabDelegateV.isClosing) {
                    tabModel.currentIndex = tabDelegateV.index;
                }
              } else if (mouse.button === Qt.RightButton) {
                  tabContextMenu.popup(mouse.x, mouse.y, this);
              }
        }

        onPositionChanged: mouse => {
            if (!pressed || tabDelegateV.isClosing || !collisionHub)
                return;

            var mouseInHub = tabDelegateV.mapToItem(collisionHub, mouse.x, mouse.y);
            targetHubX = mouseInHub.x;
            targetHubY = mouseInHub.y;

            if (!dragThresholdMet) {
                var initDistX = mouseInHub.x - clickOffsetX - tabDelegateV.mapToItem(collisionHub, 0, 0).x;
                var initDistY = mouseInHub.y - clickOffsetY - tabDelegateV.mapToItem(collisionHub, 0, 0).y;
                if ((initDistX * initDistX + initDistY * initDistY) > 25) {
                    dragThresholdMet = true;
                    tabDelegateV.isDragging = true;
                    collisionHub.dragSourceIndex = tabDelegateV.index;
                    collisionHub.dragTargetIndex = tabDelegateV.index;
                }
            }

            if (tabDelegateV.isDragging) {
                tabDelegateV.updateDragCoordinates();

                var pinThreshold = collisionHub.separatorY + (tabDelegateV.pinMorphProgress > 0.5 ? 16 : -4);
                var overPin = targetHubY < pinThreshold;

                tabDelegateV.pinMorphProgress = overPin ? 1.0 : 0.0;
                collisionHub.dragOverPinZone = overPin;

                var insideTabAreaX = targetHubX >= 0 && targetHubX <= collisionHub.width;

                if (!overPin && insideTabAreaX) {
                    var pinnedCount = tabDelegateV.localPinnedCount;
                    var normalCount = Math.max(1, tabModel.count - pinnedCount);
                    var cardCenterY = visualContentV.y + (tabDelegateV.tabHeight / 2);
                    var relY = cardCenterY - (collisionHub.tabListContainer.y + 6);
                    var rawSlot = Math.floor(relY / tabDelegateV.slotSpan);
                    var normalSlot = Math.max(0, Math.min(normalCount - 1, rawSlot));
                    var targetModelIndex = pinnedCount + normalSlot;
                    if (collisionHub.dragTargetIndex !== targetModelIndex) {
                        collisionHub.dragTargetIndex = targetModelIndex;
                    }
                } else {
                    collisionHub.dragTargetIndex = -1;
                }
            }
        }

        onReleased: mouse => {
            if (tabDelegateV.isDragging && collisionHub) {
                var droppedInPin = collisionHub.dragOverPinZone;

                if (droppedInPin) {
                    collisionHub.pinDropCommitted = true;

                    var pinTarget = collisionHub.getPinDropTarget(tabDelegateV);
                    tabDelegateV.landingWidth = pinTarget.width;

                    tabDelegateV.landX = visualContentV.x;
                    tabDelegateV.landY = visualContentV.y;
                    tabDelegateV.isLanding = true;
                    tabDelegateV.isDragging = false;

                    pinLandSpringX.stop();
                    pinLandSpringX.from = visualContentV.x;
                    pinLandSpringX.to = pinTarget.x;
                    pinLandSpringX.restart();

                    pinLandSpringY.stop();
                    pinLandSpringY.from = visualContentV.y;
                    pinLandSpringY.to = pinTarget.y;
                    pinLandSpringY.restart();

                    return;
                }

                var src = collisionHub.dragSourceIndex;
                var dst = collisionHub.dragTargetIndex;

                var pinnedCount = tabDelegateV.localPinnedCount;
                var targetModelIndex = (dst !== -1 && src !== -1) ? dst : src;
                var targetNormalSlot = Math.max(0, targetModelIndex - pinnedCount);
                var targetY = collisionHub.tabListContainer.y + 6 + (targetNormalSlot * tabDelegateV.slotSpan);
                var targetX = 8;

                tabDelegateV.landX = visualContentV.x;
                tabDelegateV.landY = visualContentV.y;
                tabDelegateV.isLanding = true;
                tabDelegateV.isDragging = false;
                tabDelegateV.pinMorphProgress = 0.0;

                normalLandSpringX.stop();
                normalLandSpringX.from = visualContentV.x;
                normalLandSpringX.to = targetX;
                normalLandSpringX.restart();

                normalLandSpringY.stop();
                normalLandSpringY.from = visualContentV.y;
                normalLandSpringY.to = targetY;
                normalLandSpringY.commitSrc = src;
                normalLandSpringY.commitDst = dst;
                normalLandSpringY.restart();
            }
        }

        onCanceled: {
            if (tabDelegateV.isDragging || tabDelegateV.isLanding) {
                tabDelegateV.isDragging = false;
                tabDelegateV.isLanding = false;
                tabDelegateV.dragX = 0.0;
                tabDelegateV.dragY = 0.0;
                tabDelegateV.landX = 0.0;
                tabDelegateV.landY = 0.0;
                tabDelegateV.pinMorphProgress = 0.0;
                if (collisionHub) {
                    collisionHub.dragSourceIndex = -1;
                    collisionHub.dragTargetIndex = -1;
                    collisionHub.dragOverPinZone = false;
                    collisionHub.pinDropCommitted = false;
                }
            }
        }
    }

    Item {
        id: visualContentV
        parent: (tabDelegateV.isDragging || tabDelegateV.isLanding) ? collisionHub : tabDelegateV
        z: (tabDelegateV.isDragging || tabDelegateV.isLanding) ? 1000 : 1

        readonly property real morphP: tabDelegateV.pinMorphProgress
        width: {
            if (tabDelegateV.isLanding && collisionHub && collisionHub.pinDropCommitted)
                return tabDelegateV.landingWidth;
            return Math.max(0, (tabDelegateV.width - 16) - (morphP * ((tabDelegateV.width - 16) - tabDelegateV.targetPinWidth)));
        }
        height: tabDelegateV.tabHeight

        x: {
            if (tabDelegateV.isLanding)
                return tabDelegateV.landX;
            if (tabDelegateV.isDragging)
                return tabDelegateV.dragX;
            return (tabDelegateV.width - width) / 2;
        }

        y: {
            if (tabDelegateV.isLanding)
                return tabDelegateV.landY;
            if (tabDelegateV.isDragging)
                return tabDelegateV.dragY;
            return tabDelegateV.animatedShift + tabDelegateV.shockwaveOffset;
        }

        opacity: tabDelegateV.isClosing ? tabDelegateV.closeOpacity : (Math.min(1.0, tabDelegateV.spawnProgress * 2.0) * Math.max(0.0, 1.0 - tabDelegateV.wsP * 1.5))

        transform: [
            Translate {
                x: (!tabDelegateV.isDragging && !tabDelegateV.isLanding) ? Math.round(tabDelegateV.wsDir * tabDelegateV.wsP * (visualContentV.width + 16)) : 0
                y: tabDelegateV.isClosing ? tabDelegateV.closeY : 0
            },
            Scale {
                origin.x: visualContentV.width / 2
                origin.y: visualContentV.height / 2
                xScale: tabDelegateV.isClosing ? tabDelegateV.closeXScale : (tabDelegateV.wsP > 0 ? (1.0 - tabDelegateV.wsP * 0.10) : (tabDelegateV.isDragging ? 1.04 : (tabMouseV.pressed ? 1.02 : 1.0)))
                yScale: tabDelegateV.isClosing ? tabDelegateV.closeYScale : (tabDelegateV.wsP > 0 ? (1.0 - tabDelegateV.wsP * 0.10) : (tabDelegateV.isDragging ? 1.04 : (tabMouseV.pressed ? 0.92 : 1.0)))

                Behavior on xScale {
                    enabled: !tabDelegateV.isClosing && tabDelegateV.wsP === 0 && !tabDelegateV.isDragging
                    CielSpring {
                        damping: 0.28
                        spring: 5.4
                        mass: 0.9
                        epsilon: 0.001
                    }
                }

                Behavior on yScale {
                    enabled: !tabDelegateV.isClosing && tabDelegateV.wsP === 0 && !tabDelegateV.isDragging
                    CielSpring {
                        damping: 0.28
                        spring: 5.4
                        mass: 0.9
                        epsilon: 0.001
                    }
                }
            }
        ]

        CielSquircle {
            anchors.fill: parent
            color: Theme.surface
            borderWidth: tabDelegateV.isDragging ? 1 : 0
            borderColor: Theme.border
            opacity: (tabDelegateV.isCurrent || tabDelegateV.isDragging) ? 1.0 : (tabDelegateV.isHovered ? 0.6 : 0.0)

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }
        }

        Rectangle {
            id: closeBtnContainer
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: -6
            anchors.topMargin: -6
            
            width: closeBtnPop.width - 4 
            height: width
            radius: width / 2
            color: Theme.surface

            opacity: (tabDelegateV.collapsed && visualContentV.morphP < 0.1 && tabModel.count > 1 && tabDelegateV.isHovered) ? 1.0 : 0.0
            scale: (tabDelegateV.collapsed && visualContentV.morphP < 0.1 && tabModel.count > 1 && tabDelegateV.isHovered) ? 1.0 : 0.0
            visible: opacity > 0.0

            Behavior on opacity {
                CielSpring {
                    damping: 0.28
                    spring: 5.4
                    mass: 0.9
                    epsilon: 0.001
                }
            }

            Behavior on scale {
                CielSpring {
                    damping: 0.28
                    spring: 5.4
                    mass: 0.9
                    epsilon: 0.001
                }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.15)
                shadowBlur: 0.3                   
                shadowVerticalOffset: 2          
            }

            CielIconButton {
                id: closeBtnPop
                anchors.centerIn: parent 
                icon: "x"
                size: Theme.XXSMALL
                onClicked: tabDelegateV.requestClose()
            }
        }

        Item {
            id: iconContainerV
            width: 40
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            x: ((visualContentV.width - width) / 2) * visualContentV.morphP

            CielLoadingSpinner {
                anchors.centerIn: parent
                implicitWidth: 16
                implicitHeight: 16
                orbitRadius: 4.5
                minDotSize: 1.2
                maxDotSize: 3.2
                finalSize: 2.8
                finished: !tabDelegateV.loading
                color: Theme.accent
                visible: !finished
            }

            Image {
                id: faviconV
                anchors.centerIn: parent
                width: 16
                height: 16
                sourceSize.width: 32
                sourceSize.height: 32
                fillMode: Image.PreserveAspectFit
                source: tabDelegateV.siteFavicon
                visible: status === Image.Ready && !tabDelegateV.loading
            }

            CielIcon {
                anchors.centerIn: parent
                icon: tabDelegateV.url.toString().indexOf("history") !== -1 ? "clock-counter-clockwise" : "globe"
                size: Theme.XSMALL
                color: tabDelegateV.isCurrent ? Theme.textPrimary : Theme.textSecondary
                visible: !faviconV.visible && !tabDelegateV.loading
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 40
            anchors.right: closeBtnV.visible ? closeBtnV.left : parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            opacity: (tabDelegateV.collapsed || visualContentV.morphP > 0.1) ? 0.0 : (1.0 - visualContentV.morphP * 2.0)
            text: tabDelegateV.displayTitle
            font.pixelSize: 12
            font.weight: tabDelegateV.isCurrent ? Font.Medium : Font.Normal
            color: tabDelegateV.isCurrent ? Theme.textPrimary : Theme.textSecondary
            elide: Text.ElideRight

            Behavior on opacity {
                NumberAnimation {
                    duration: 80
                }
            }
        }

        CielIconButton {
            id: closeBtnV
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            icon: "x"
            size: Theme.XSMALL
            opacity: (!tabDelegateV.collapsed && visualContentV.morphP < 0.1 && tabModel.count > 1 && (tabDelegateV.isHovered || tabDelegateV.isCurrent)) ? 1.0 : 0.0
            visible: opacity > 0.0
            onClicked: tabDelegateV.requestClose()
        }
    }


CielContextMenu {
    id: tabContextMenu
    // trigger: visualContentV
    // useAbsoluteCoordinates: true


    CielMenuItem {
        text: "New tab to the bottom"
        icon: ""

        onTriggered: {
            tabDelegateV.createTabBelow("about:blank");
            tabContextMenu.close();
        }
    }

    
    CielMenuItem {
        text: "Duplicate"
        icon: ""

        onTriggered: {
            tabDelegateV.duplicateTab();
            tabContextMenu.close();
        }
    }

    CielMenuSeparator {}

    CielMenuItem {
        text: "Reload"
        icon: "arrow-clockwise"
        onTriggered: {
            var page = tabDelegateV.currentTabView;
            if (page && page.engine)
                page.engine.reload();

            tabContextMenu.close();
        }
    }

    CielMenuItem {
        text: "Pin"
        icon: "push-pin"

        onTriggered: {
            tabModel.togglePin(tabDelegateV.index);
            tabContextMenu.close();
        }
    }

    CielMenuItem {
        text: "Close"
        icon: "x"

        onTriggered: {
            tabContextMenu.close();
            tabDelegateV.requestClose();
        }
    }

    CielMenuSeparator {}

    CielMenuItem {
        text: "Close other tabs"
        icon: ""

        onTriggered: {
            tabContextMenu.close();
            tabDelegateV.closeOtherTabs();
        }
    }

    CielMenuItem {
        text: "Close tabs to the bottom"
        icon: ""

        onTriggered: {
            tabContextMenu.close();
            tabDelegateV.closeTabsToBottom();
        }
    }
}
}
