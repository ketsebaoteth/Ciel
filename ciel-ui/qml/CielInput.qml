import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ciel.Ui

Item {
    id: root

    property alias text: inputField.text
    property string placeholder: ""
    property alias inputField: inputField
    readonly property bool isInputActive: inputField.activeFocus
    property bool isPrimary: false
    property var preContent: null
    property var postContent: null
    property bool showBorder: true

    signal accepted(string query)

    readonly property bool isPressed: mouseArea.pressed || inputField.pressed

    implicitWidth: 300
    implicitHeight: 32

    scale: isPressed ? 0.988 : 1.0
    transformOrigin: Item.Center

    layer.enabled: scaleAnimation.running
    layer.smooth: true

    Behavior on scale {
        CielSpring {
            id: scaleAnimation
            damping: 4.85
            spring: 8.0
            mass: 4.0
            epsilon: 0.005
        }
    }

    CielSquircle {
        id: baseBackground
        anchors.fill: parent
        color: root.isPrimary ? Theme.background : Theme.transparent
        borderWidth: root.isPrimary ? 0 : 1
        borderColor: Theme.border
    }

    CielSquircle {
        id: focusHighlight
        anchors.fill: parent
        color: "transparent"
        borderWidth: root.showBorder ? 1 : 0
        borderColor: Theme.accent
        opacity: inputField.activeFocus ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: inputField.forceActiveFocus()
    }

    onPreContentChanged: {
        if (root.preContent && typeof root.preContent.createObject !== "function") {
            root.preContent.parent = preSlot;
        }
    }

    onPostContentChanged: {
        if (root.postContent && typeof root.postContent.createObject !== "function") {
            root.postContent.parent = postSlot;
        }
    }

    RowLayout {
        id: contentRow
        anchors.fill: parent
        anchors.leftMargin: root.preContent ? 4 : 10
        anchors.rightMargin: root.postContent ? 4 : 10
        spacing: 4

        Loader {
            id: preLoader
            visible: Boolean(root.preContent && typeof root.preContent.createObject === "function")
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: (root.preContent && typeof root.preContent.createObject === "function") ? root.preContent : null
        }

        Item {
            id: preSlot
            visible: Boolean(root.preContent && typeof root.preContent.createObject !== "function")
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }

        TextField {
            id: inputField
            Layout.fillWidth: true
            Layout.fillHeight: true

            placeholderText: root.placeholder
            font.pixelSize: 13
            verticalAlignment: TextInput.AlignVCenter

            color: Theme.textPrimary
            placeholderTextColor: Theme.textSecondary

            background: null
            selectByMouse: true
            clip: true

            onActiveFocusChanged: {
                if (activeFocus) {
                    Qt.callLater(selectAll);
                } else {
                    cursorPosition = 0;
                    ensureVisible(0);
                }
            }

            onAccepted: root.accepted(inputField.text)
        }

        Loader {
            id: postLoader
            visible: Boolean(root.postContent && typeof root.postContent.createObject === "function")
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: (root.postContent && typeof root.postContent.createObject === "function") ? root.postContent : null
        }

        Item {
            id: postSlot
            visible: Boolean(root.postContent && typeof root.postContent.createObject !== "function")
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
