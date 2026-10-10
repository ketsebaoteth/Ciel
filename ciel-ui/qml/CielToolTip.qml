import QtQuick
import QtQuick.Layouts
import Ciel.Ui 1.0
import QtQuick
// Ensure you have the necessary imports for CielSpring, CielSquircle, and Theme

Item {
    id: root
    
    // Force attachment to the window's contentItem to ensure it overlays everything 
    // and isn't clipped by parent boundaries
    parent: root.Window.window ? root.Window.window.contentItem : null
    anchors.fill: parent
    
    property string text: ""
    property Item trigger: null
    property real requestedX: 0
    property real requestedY: 0
    property bool useAbsoluteCoordinates: false
    
    property bool isOpen: false
    property int zIndex: 100000
    
    property real openProgress: isOpen ? 1.0 : 0.0

    // Entry/Exit Animation
    Behavior on openProgress {
        CielSpring {
            damping: 0.35
            spring: 5.5
            mass: 0.9
            epsilon: 0.001
        }
    }

    function open() {
        // if (!isOpen) {
            updateCoordinates();
            isOpen = true;
        //}
    }

    // Add this Timer to delay the actual close state
    Timer {
        id: closeDelay
        interval: 60 // Matches roughly the spring animation settle time
        onTriggered: {
            root.isOpen = false;
            root.useAbsoluteCoordinates = false;
        }
    }

    // 1. Add a configurable delay property (500ms is standard for tooltips)
    property int openDelay: 500

    // 2. Add the open timer
    Timer {
        id: openTimer
        interval: root.openDelay
        onTriggered: {
            updateCoordinates(); // Apply the latest coordinates right before showing
            root.isOpen = true;
        }
    }

    // 3. Update openAt to use the timer
    function openAt(absoluteX, absoluteY) {
        // Always update coordinates so they are ready when the timer fires
        root.requestedX = absoluteX;
        root.requestedY = absoluteY;
        root.useAbsoluteCoordinates = true;

        if (isOpen) return; // Already open, ignore

        // If it was in the middle of closing, cancel the close
        if (closeDelay.running) {
            closeDelay.stop();
        }

        // Start the delay timer (if not already running from a previous micro-movement)
        if (!openTimer.running) {
            openTimer.start();
        }
    }

    // 4. Update close to cancel the open timer
    function close() {
        openTimer.stop(); // Crucial: prevents tooltip from opening if mouse leaves before delay finishes
        closeDelay.restart(); 
    }

    function updateCoordinates() {
        if (!root.Window.window) return;

        if (root.useAbsoluteCoordinates) {
            var leftMargin = 8;
            var rightMargin = 8;
            var bottomMargin = 8;
            var topMargin = 50; // Increased top margin to avoid title bar / top edge clipping

            // Calculate the maximum allowed X and Y to prevent off-screen rendering
            var maxX = root.width - menuCard.width - rightMargin;
            var maxY = root.height - menuCard.height - bottomMargin;
            
            // Clamp the requested coordinates within the safe window bounds
            menuCard.x = Math.max(leftMargin, Math.min(root.requestedX, maxX));
            menuCard.y = Math.max(topMargin, Math.min(root.requestedY, maxY));
            
            menuCard.transformOrigin = Item.TopLeft;
        }
    }

    visible: isOpen || menuCard.opacity > 0.0
    z: root.zIndex

    Item {
        id: menuCard
        width: Math.max(60, Math.min(400, tooltipText.implicitWidth + 24))
        height: tooltipText.implicitHeight + 16
        
        scale: 0.94 + (root.openProgress * 0.06)
        opacity: root.openProgress

        CielSquircle {
            anchors.fill: parent
            color: Theme.surface
            borderWidth: 1
            borderColor: Theme.border
        }

        Text {
            id: tooltipText
            anchors.centerIn: parent
            anchors.margins: 8
            text: root.text
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Theme.textPrimary
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
