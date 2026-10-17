import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ciel.Ui

Item {
    id: root

    property bool isOpen: false
    property bool closeOnBackdrop: true
    property real contentWidth: 440
    property real contentHeight: 280

    property Item trigger: null
    property real triggerGap: 6

    property bool triggerMode: false
    property bool showBackdrop: true

    property Item originalParent: null

    property real triggerX: 0
    property real triggerY: 0

    default property alias content: cardContent.data
    property alias cardColor: popupCard.color
    property alias borderColor: popupCard.borderColor
    property alias borderWidth: popupCard.borderWidth

    signal opened
    signal closed
    signal afterClosed

    readonly property real targetX: root.triggerMode ? root.triggerX : Math.round((root.width - root.contentWidth) / 2)

    readonly property real targetY: root.triggerMode ? root.triggerY : Math.round((root.height - root.contentHeight) / 2)

    readonly property real startYOffset: 16
    readonly property real startXScale: 1.1 // 0.86
    readonly property real startYScale: 1.08 // 0.76

    readonly property real springY: 4.2
    readonly property real dampingY: 0.34
    readonly property real springX: 4.5
    readonly property real dampingX: 0.36
    readonly property real springPosY: 4.2
    readonly property real dampingPosY: 0.34

    readonly property int fadeInDuration: 110
    readonly property int closeDuration: 130

    anchors.fill: parent
    z: 9999
    visible: root.isOpen || openAnim.running || closeAnim.running

    function open() {
        root.triggerMode = false;
        root.showBackdrop = true;

        if (root.isOpen && !closeAnim.running)
            return;

        root.isOpen = true;
        closeAnim.stop();
        openAnim.restart();
        root.opened();
    }

    function openFromTrigger(item) {
        if (!item || !Window.window) {
            open();
            return;
        }

        root.trigger = item;

        if (!root.originalParent)
            root.originalParent = root.parent;

        var win = Window.window;
        var triggerPos = item.mapToItem(win.contentItem, 0, 0);
        var margin = 8;

        var targetX = triggerPos.x + item.width + root.triggerGap;

        var targetY = triggerPos.y;

        // Flip to the left when there isn't enough room on the right.
        if (targetX + root.contentWidth > win.width - margin) {
            targetX = triggerPos.x - root.contentWidth - root.triggerGap;
        }

        // Clamp horizontally.
        targetX = Math.max(margin, Math.min(win.width - root.contentWidth - margin, targetX));

        // Clamp vertically.
        targetY = Math.max(margin, Math.min(win.height - root.contentHeight - margin, targetY));

        root.triggerX = targetX;
        root.triggerY = targetY;

        // Move the popup overlay to the window coordinate system.
        root.parent = win.contentItem;

        root.triggerMode = true;
        root.showBackdrop = false;
        root.isOpen = true;

        closeAnim.stop();
        openAnim.restart();

        root.opened();
    }

    function close() {
        if (!root.isOpen && !openAnim.running)
            return;

        root.isOpen = false;
        openAnim.stop();
        closeAnim.restart();
        root.closed();
    }

    function toggle() {
        if (root.isOpen)
            root.close();
        else
            root.open();
    }

    MouseArea {
        id: eventBlocker

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        preventStealing: true
        cursorShape: Qt.ArrowCursor

        onWheel: wheel => wheel.accepted = true

        onClicked: mouse => {
            mouse.accepted = true;

            if (root.closeOnBackdrop && root.isOpen)
                root.close();
        }

        Rectangle {
            id: backdropDim

            anchors.fill: parent
            color: "#000000"
            opacity: 0.0
        }
    }

    Item {
        id: cardWrapper

        x: root.targetX
        y: root.targetY + root.startYOffset

        width: root.contentWidth
        height: root.contentHeight

        opacity: 0.0

        transform: Scale {
            id: scaleTransform

            origin.x: cardWrapper.width / 2
            origin.y: cardWrapper.height / 2

            xScale: root.startXScale
            yScale: root.startYScale
        }

        MouseArea {
            anchors.fill: parent

            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            preventStealing: true

            onWheel: wheel => wheel.accepted = true
            onClicked: mouse => mouse.accepted = true
        }

        CielSquircle {
            id: popupCard

            anchors.fill: parent

            radius: 20
            color: Theme.surface
            borderWidth: 1
            borderColor: Theme.border

            Item {
                id: cardContent

                anchors.fill: parent
                anchors.margins: 1
            }
        }
    }

    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: backdropDim
            property: "opacity"

            from: 0.0
            to: root.showBackdrop ? 0.3 : 0.0

            duration: 240
            easing.type: Easing.OutQuad
        }

        SpringAnimation {
            target: cardWrapper
            property: "y"

            from: root.targetY + root.startYOffset
            to: root.targetY

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
            target: cardWrapper
            property: "opacity"

            from: 0.0
            to: 1.0

            duration: root.fadeInDuration
            easing.type: Easing.OutQuad
        }
    }

    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: backdropDim
            property: "opacity"

            to: 0.0

            duration: root.closeDuration
            easing.type: Easing.InQuad
        }

        NumberAnimation {
            target: cardWrapper
            property: "y"

            to: root.targetY + 12

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
            target: cardWrapper
            property: "opacity"

            to: 0.0

            duration: root.closeDuration - 10
            easing.type: Easing.InQuad
        }

        onFinished: {
            if (root.triggerMode && root.originalParent) {
                root.parent = root.originalParent;
                root.triggerMode = false;
            }
            afterClosed();
        }
    }
}
