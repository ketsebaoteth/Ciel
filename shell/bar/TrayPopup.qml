import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ciel.Ui

PopupWindow {
    id: trayPopup

    property var targetWindow
    property var trayItem: null
    property rect anchorRect: Qt.rect(0, 0, 0, 0)
    property bool isOpen: false

    property int hoverIndex: -1

    readonly property var entries: menuOpener.children ? menuOpener.children.values : []

    readonly property bool anyCheckable: {
        var list = entries;
        for (var i = 0; i < list.length; ++i) {
            var e = list[i];
            if (e && !e.isSeparator && e.buttonType !== QsMenuButtonType.None)
                return true;
        }
        return false;
    }

    readonly property bool anyIcon: {
        var list = entries;
        for (var i = 0; i < list.length; ++i) {
            var e = list[i];
            if (e && !e.isSeparator && e.icon && e.icon !== "")
                return true;
        }
        return false;
    }

    readonly property string headerTitle: trayItem ? (trayItem.tooltipTitle || trayItem.title || trayItem.id || "") : ""
    readonly property bool showHeader: headerTitle !== ""

    readonly property real startY: -14
    readonly property real startXScale: 0.88
    readonly property real startYScale: 0.78

    readonly property real springY: 4.2
    readonly property real dampingY: 0.34
    readonly property real springX: 4.5
    readonly property real dampingX: 0.36
    readonly property real springPosY: 4.2
    readonly property real dampingPosY: 0.34

    readonly property int fadeInDuration: 95
    readonly property int closeDuration: 130

    readonly property int maxHeight: 440
    readonly property int rowHeight: 32

    property var activeDropdown: null

    function cleanText(t) {
        return (t || "").replace(/__/g, "\u0001").replace(/_/g, "").replace(/\u0001/g, "_");
    }

    function selectable(e) {
        return !!e && !e.isSeparator && e.enabled;
    }

    function close() {
        isOpen = false;
    }

    function openSubmenu(i) {
        var item = menuRepeater.itemAt(i);
        if (!item || !item.entry || !item.entry.hasChildren)
            return;

        var dd = item.dropdown;
        if (!dd)
            return;

        trayPopup.activeDropdown = dd;

        if (dd.isOpen === true) {
            if (dd.close)
                dd.close();
            return;
        }

        if (dd.open)
            dd.open();
        else if (dd.toggle)
            dd.toggle();
        else
            dd.isOpen = true;
    }

    function activateIndex(i) {
        var list = entries;
        if (i < 0 || i >= list.length)
            return;

        var e = list[i];
        if (!selectable(e))
            return;

        if (e.hasChildren) {
            openSubmenu(i);
        } else {
            e.triggered();
            close();
        }
    }

    function ensureVisible(i) {
        var item = menuRepeater.itemAt(i);
        if (!item)
            return;

        var top = item.mapToItem(menuColumn, 0, 0).y;
        var bottom = top + item.height;

        if (top < menuScroll.contentY)
            menuScroll.contentY = Math.max(0, top - 4);
        else if (bottom > menuScroll.contentY + menuScroll.height)
            menuScroll.contentY = Math.min(menuScroll.contentHeight - menuScroll.height, bottom - menuScroll.height + 4);
    }

    function move(dir) {
        var list = entries;
        if (list.length === 0)
            return;

        var i = hoverIndex;
        for (var n = 0; n < list.length; ++n) {
            if (i < 0)
                i = dir > 0 ? 0 : list.length - 1;
            else
                i = (i + dir + list.length) % list.length;

            if (selectable(list[i])) {
                hoverIndex = i;
                ensureVisible(i);
                return;
            }
        }
    }

    function moveEdge(dir) {
        hoverIndex = -1;
        move(dir);
    }

    Shortcut {
        sequence: "Escape"
        enabled: trayPopup.isOpen
        onActivated: trayPopup.close()
    }

    Shortcut {
        sequence: "Down"
        enabled: trayPopup.isOpen
        onActivated: trayPopup.move(1)
    }

    Shortcut {
        sequence: "Up"
        enabled: trayPopup.isOpen
        onActivated: trayPopup.move(-1)
    }

    Shortcut {
        sequence: "Home"
        enabled: trayPopup.isOpen
        onActivated: trayPopup.moveEdge(1)
    }

    Shortcut {
        sequence: "End"
        enabled: trayPopup.isOpen
        onActivated: trayPopup.moveEdge(-1)
    }

    Shortcut {
        sequence: "Return"
        enabled: trayPopup.isOpen
        onActivated: trayPopup.activateIndex(trayPopup.hoverIndex)
    }

    Shortcut {
        sequence: "Enter"
        enabled: trayPopup.isOpen
        onActivated: trayPopup.activateIndex(trayPopup.hoverIndex)
    }

    Shortcut {
        sequence: "Space"
        enabled: trayPopup.isOpen
        onActivated: trayPopup.activateIndex(trayPopup.hoverIndex)
    }

    Shortcut {
        sequence: "Right"
        enabled: trayPopup.isOpen
        onActivated: trayPopup.openSubmenu(trayPopup.hoverIndex)
    }

    grabFocus: false

    HyprlandFocusGrab {
        windows: [trayPopup]
        active: trayPopup.isOpen

        onCleared: {
            if (!trayPopup.isOpen)
                return;

            for (var i = 0; i < menuRepeater.count; ++i) {
                var item = menuRepeater.itemAt(i);
                if (item && item.dropdownOpen)
                    return;
            }

            trayPopup.isOpen = false;
        }
    }

    onTrayItemChanged: {
        hoverIndex = -1;
        activeDropdown = null;
        if (!trayItem)
            isOpen = false;
    }

    onIsOpenChanged: {
        if (isOpen) {
            hoverIndex = -1;
            activeDropdown = null;
            menuScroll.contentY = 0;
            closeAnim.stop();
            openAnim.restart();
        } else {
            openAnim.stop();
            closeAnim.restart();
        }
    }

    readonly property int submenuSpace: 290
    implicitWidth: popupContent.width + 60 + submenuSpace * 2
    implicitHeight: maxHeight + 120
    color: "transparent"

    visible: isOpen || openAnim.running || closeAnim.running

    anchor.window: targetWindow
    anchor.rect: trayPopup.anchorRect
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.Flip

    QsMenuOpener {
        id: menuOpener
        menu: trayPopup.trayItem ? trayPopup.trayItem.menu : null
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: trayPopup.close()
    }

    RectangularShadow {
        anchors.fill: popupContent
        radius: 18
        offset.y: 12
        blur: 42
        spread: -8
        color: "#00000080"
        opacity: popupContent.opacity
    }

    Item {
        id: popupContent

        property real radius: 18

        width: 248
        height: Math.min(trayPopup.maxHeight, menuColumn.implicitHeight + 16)

        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        opacity: 0.0

        Behavior on height {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        transform: Scale {
            id: scaleTransform
            origin.x: popupContent.width / 2
            origin.y: 0
            xScale: trayPopup.startXScale
            yScale: trayPopup.startYScale
        }

        CielSquircle {
            anchors.fill: parent
            radius: popupContent.radius
            color: Theme.surface
            borderColor: Theme.surfaceHover
            borderWidth: 1
        }

        MouseArea {
            anchors.fill: parent
        }

        SequentialAnimation {
            id: openAnim

            ParallelAnimation {
                SpringAnimation {
                    target: popupContent
                    property: "y"
                    from: trayPopup.startY
                    to: 0
                    spring: trayPopup.springPosY
                    damping: trayPopup.dampingPosY
                    epsilon: 0.001
                }
                SpringAnimation {
                    target: scaleTransform
                    property: "yScale"
                    from: trayPopup.startYScale
                    to: 1.0
                    spring: trayPopup.springY
                    damping: trayPopup.dampingY
                    epsilon: 0.001
                }
                SpringAnimation {
                    target: scaleTransform
                    property: "xScale"
                    from: trayPopup.startXScale
                    to: 1.0
                    spring: trayPopup.springX
                    damping: trayPopup.dampingX
                    epsilon: 0.001
                }
                NumberAnimation {
                    target: popupContent
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: trayPopup.fadeInDuration
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: menuScroll
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: 180
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: menuTranslate
                    property: "y"
                    from: 8
                    to: 0
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }
        }

        ParallelAnimation {
            id: closeAnim

            NumberAnimation {
                target: popupContent
                property: "y"
                to: trayPopup.startY
                duration: trayPopup.closeDuration
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: scaleTransform
                property: "yScale"
                to: trayPopup.startYScale
                duration: trayPopup.closeDuration + 10
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: scaleTransform
                property: "xScale"
                to: trayPopup.startXScale
                duration: trayPopup.closeDuration + 10
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: popupContent
                property: "opacity"
                to: 0.0
                duration: trayPopup.closeDuration - 10
                easing.type: Easing.InQuad
            }
        }

        Flickable {
            id: menuScroll

            anchors.fill: parent
            anchors.margins: 8

            contentWidth: width
            contentHeight: menuColumn.implicitHeight

            clip: true
            boundsBehavior: Flickable.StopAtBounds

            transform: Translate {
                id: menuTranslate
                x: 0
                y: 0
            }

            ColumnLayout {
                id: menuColumn

                width: menuScroll.width
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    visible: trayPopup.showHeader
                    spacing: 8

                    Image {
                        visible: status === Image.Ready
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        source: trayPopup.trayItem && trayPopup.trayItem.icon ? String(trayPopup.trayItem.icon) : ""
                        sourceSize: Qt.size(32, 32)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: trayPopup.headerTitle
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    Layout.topMargin: 2
                    Layout.bottomMargin: 2

                    visible: trayPopup.showHeader
                    color: Theme.surfaceHover
                }

                Repeater {
                    id: menuRepeater
                    model: menuOpener.children

                    delegate: Item {
                        id: row

                        required property int index
                        required property var modelData

                        readonly property var entry: modelData
                        readonly property bool isSep: entry ? entry.isSeparator : false
                        readonly property bool usable: trayPopup.selectable(entry)
                        readonly property bool hasSub: entry ? (!entry.isSeparator && entry.hasChildren) : false
                        readonly property bool hovered: usable && trayPopup.hoverIndex === index
                        readonly property bool isCheckbox: entry && entry.buttonType === QsMenuButtonType.CheckBox
                        readonly property bool isRadio: entry && entry.buttonType === QsMenuButtonType.RadioButton
                        readonly property bool isChecked: entry && entry.checkState === Qt.Checked
                        readonly property bool isPartial: entry && entry.checkState === Qt.PartiallyChecked

                        readonly property var dropdown: ddLoader.item
                        readonly property bool dropdownOpen: !!dropdown && dropdown.isOpen === true

                        Layout.fillWidth: true
                        Layout.preferredHeight: isSep ? 9 : trayPopup.rowHeight

                        Rectangle {
                            visible: row.isSep

                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6

                            height: 1
                            color: Theme.surfaceHover
                        }

                        Rectangle {
                            visible: !row.isSep
                            anchors.fill: parent
                            radius: 9
                            color: Theme.surfaceHover
                            opacity: (row.hovered || row.dropdownOpen) ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 90
                                }
                            }
                        }

                        RowLayout {
                            visible: !row.isSep
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8
                            opacity: row.entry && row.entry.enabled ? 1.0 : 0.4

                            Item {
				id: checkBox

                                visible: row.isCheckbox || row.isRadio
                                Layout.preferredWidth: 14
                                Layout.preferredHeight: 14

                                CielIcon {
                                    visible: row.isCheckbox && (row.isChecked || row.isPartial)
                                    anchors.centerIn: parent
                                    icon: row.isPartial ? "minus" : "check"
                                    size: Theme.SMALL
                                    color: Theme.accent
                                }

                                Rectangle {
                                    visible: row.isRadio && row.isChecked
                                    anchors.centerIn: parent
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: Theme.accent
                                }
                            }

                            Item {
				id: icon

                                visible: !!row.entry && !!row.entry.icon && row.entry.icon !== "" && entryIcon.status !== Image.Error
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16

                                Image {
                                    id: entryIcon
                                    anchors.fill: parent
                                    visible: status === Image.Ready
                                    source: row.entry && row.entry.icon ? row.entry.icon : ""
                                    sourceSize: Qt.size(32, 32)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }

			    Item {
				visible: !(icon.visible || checkBox.visible)
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
			    }

                            Text {
                                Layout.fillWidth: true
                                text: row.entry ? trayPopup.cleanText(row.entry.text) : ""
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                renderType: Text.NativeRendering
                            }

                            CielIcon {
                                visible: row.hasSub
                                icon: "caret-right"
                                size: Theme.SMALL
                                color: Theme.textSecondary
                            }
                        }

                        HoverHandler {
                            enabled: row.usable && !row.isSep
                            cursorShape: Qt.PointingHandCursor

                            onHoveredChanged: {
                                if (hovered)
                                    trayPopup.hoverIndex = row.index;
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: row.usable
                            onClicked: trayPopup.activateIndex(row.index)
                        }

                        Loader {
                            id: ddLoader
                            active: row.hasSub

                            sourceComponent: TrayDropDown {
                                trigger: row
                                entry: row.entry
                                popup: trayPopup
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: trayPopup.rowHeight
                    visible: trayPopup.entries.length === 0

                    Text {
                        anchors.centerIn: parent
                        text: trayPopup.trayItem && trayPopup.trayItem.hasMenu ? "Loading…" : "No menu available"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        Rectangle {
            visible: menuScroll.contentHeight > menuScroll.height + 1
            anchors.right: parent.right
            anchors.rightMargin: 3
            width: 3
            radius: 1.5
            color: Theme.textSecondary
            opacity: 0.45

            height: Math.max(20, (menuScroll.height / menuScroll.contentHeight) * menuScroll.height)
            y: 8 + (menuScroll.contentHeight > menuScroll.height
                    ? (menuScroll.contentY / (menuScroll.contentHeight - menuScroll.height)) * (menuScroll.height - height)
                    : 0)
        }
    }
}
