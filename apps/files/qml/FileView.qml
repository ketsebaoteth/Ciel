import QtQuick
import QtQuick.Window
import QtQuick.Controls as T
import QtQuick.Layouts
import Ciel.Ui
import Ciel.Files
import QtQuick.Controls

Item {
    id: root
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    property var breadcrumbModel: []

    property int quickSidebarWidth: 200
    property int quickSidebarMinWidth: 130
    property int quickSidebarMaxWidth: 300

    property bool editingPath: false
    Keys.onPressed: function (event) {
        var cur = FileListModel.focusedRow;
        var count = FileListModel.rowCount();
        var mods = event.modifiers;

        switch (event.key) {
        case Qt.Key_Left:
            FileListModel.navigate(cur - 1, mods);
            event.accepted = true;
            break;
        case Qt.Key_C:
            if (event.modifiers & Qt.ControlModifier) {
                if (event.modifiers & Qt.ShiftModifier) {
                    TabManager.setClipboardText(TabManager.currentPath);
                }
                TabManager.setCutMode(false);
                TabManager.addSelectedToClipboard();
                event.accepted = true;
            }
            break;
        case Qt.Key_X:
            if (event.modifiers & Qt.ControlModifier) {
                TabManager.setCutMode(true);
                TabManager.addSelectedToClipboard();
                event.accepted = true;
            }
            break;
        case Qt.Key_V:
            if (event.modifiers & Qt.ControlModifier) {
                TabManager.paste();
                event.accepted = true;
            }
            break;
        case Qt.Key_Right:
            FileListModel.navigate(cur + 1, mods);
            event.accepted = true;
            break;
        case Qt.Key_Up:
            FileListModel.navigate(cur - viewArea.columns, mods);
            event.accepted = true;
            break;
        case Qt.Key_Down:
            FileListModel.navigate(cur + viewArea.columns, mods);
            event.accepted = true;
            break;
        case Qt.Key_Home:
            FileListModel.navigate(0, mods);
            event.accepted = true;
            break;
        case Qt.Key_End:
            FileListModel.navigate(count - 1, mods);
            event.accepted = true;
            break;
        case Qt.Key_PageUp:
            FileListModel.navigate(cur - viewArea.pageSize, mods);
            event.accepted = true;
            break;
        case Qt.Key_PageDown:
            FileListModel.navigate(cur + viewArea.pageSize, mods);
            event.accepted = true;
            break;
        case Qt.Key_A:
            if (event.modifiers & Qt.ControlModifier) {
                FileListModel.selectAll();
                event.accepted = true;
            }
            break;
        case Qt.Key_Escape:
            FileListModel.clearSelection();
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            var name = FileListModel.data(FileListModel.index(cur, 0), FileListModel.NameRole);
            var isDir = FileListModel.data(FileListModel.index(cur, 0), FileListModel.IsDirRole);
            if (isDir) {
                TabManager.openFolder(name);
            }
            event.accepted = true;
            break;
        case Qt.Key_Space:
            FileListModel.handleSelection(cur, mods);
            event.accepted = true;
            break;
        case Qt.Key_Delete:
            if (event.modifiers & Qt.ShiftModifier) {
                permDeletePopup.open();
            } else {
                TabManager.deleteSelected(false);
                event.accepted = true;
            }
        default:
            if (event.text.length > 0 && !event.modifiers) {
                viewArea.typeAheadBuffer += event.text.toLowerCase();
                typeAheadTimer.restart();
                var target = FileListModel.findNextByPrefix(viewArea.typeAheadBuffer);
                if (target !== -1) {
                    FileListModel.navigate(target, 0);
                }
                event.accepted = true;
            }
            break;
        }
    }
    function updateBreadcrumb() {
        const parts = TabManager.currentPath.split("/").filter(p => p !== "");

        let result = [];
        let path = "";

        // Root
        result.push({
            title: "/",
            path: "/"
        });

        for (const part of parts) {
            path += "/" + part;

            result.push({
                title: part,
                path: path
            });
        }

        breadcrumbModel = result;
    }
    Component.onCompleted: updateBreadcrumb()
    Connections {
        target: TabManager

        function onCopyProgress(copied, total, file) {
            transferPopup.currentFile = file;
            transferPopup.progress = total > 0 ? (copied / total) : 0.0;
            if (!transferPopup.hasConflict) {
                transferPopup.open();
            }
        }

        function onConflictDetected(fileName) {
            transferPopup.conflictFile = fileName;
            transferPopup.open();
        }

        function onOperationFailed(errorMsg) {
            transferPopup.close();
            pathErrorPopup.title = "Operation Failed";
            pathErrorPopup.message = errorMsg;
            pathErrorPopup.open();
        }

        function onCopyFinished() {
            transferPopup.conflictFile = "";
            transferPopup.close();
        }
    }
    Connections {
        target: TabManager
        function onCurrentPathChanged() {
            updateBreadcrumb();
        }
    }
    property int navigationIconSize: Theme.SMALL
    ListModel {
        id: placesModel

        ListElement {
            name: "Home"
            iconName: "house-simple"
            location: "home"
        }

        ListElement {
            name: "Desktop"
            iconName: "desktop"
            location: "desktop"
        }

        ListElement {
            name: "Documents"
            iconName: "file-text"
            location: "documents"
        }

        ListElement {
            name: "Downloads"
            iconName: "download-simple"
            location: "downloads"
        }

        ListElement {
            name: "Pictures"
            iconName: "images"
            location: "pictures"
        }

        ListElement {
            name: "Music"
            iconName: "music-notes"
            location: "music"
        }

        ListElement {
            name: "Videos"
            iconName: "video-camera"
            location: "videos"
        }

        ListElement {
            name: "Trash"
            iconName: "trash"
            location: "trash"
        }
    }
    Rectangle {
        anchors.fill: parent
        color: Theme.surface
    }

    CielFocusWrapper {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.margins: 13
                Layout.preferredHeight: 36
                spacing: 20

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 12

                    CielIconButton {
                        icon: "arrow-left"
                        iconSize: root.navigationIconSize
                    }

                    CielIconButton {
                        icon: "arrow-right"
                        iconSize: root.navigationIconSize
                    }

                    CielIconButton {
                        icon: "arrow-up"
                        iconSize: root.navigationIconSize
                        onClicked: TabManager.goUp()
                    }

                    CielIconButton {
                        icon: "arrows-clockwise"
                        iconSize: root.navigationIconSize
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    CielSquircle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.background
                        CielBreadCrumb {
                            visible: !editingPath
                            anchors.fill: parent
                            anchors.margins: 8
                            model: root.breadcrumbModel
                        }
                        TextInput {
                            id: pathInput
                            anchors.fill: parent
                            anchors.margins: 8
                            verticalAlignment: TextInput.AlignVCenter
                            visible: editingPath
                            color: Theme.textPrimary
                            selectByMouse: true
                            text: TabManager.currentPath
                            focus: editingPath
                            onAccepted: {
                                if (TabManager.setCurrentPath(text)) {
                                    root.editingPath = false;
                                } else {
                                    pathErrorPopup.title = "Invalid path";
                                    pathErrorPopup.message = "The specified directory does not exist.";
                                    pathErrorPopup.open();
                                }
                            }

                            onActiveFocusChanged: {
                                if (!activeFocus)
                                    root.editingPath = false;
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !editingPath

                            onClicked: {
                                pathInput.text = TabManager.currentPath;
                                pathInput.selectAll();
                                root.editingPath = true;
                                pathInput.forceActiveFocus();
                            }
                        }
                    }

                    CielSearch {
                        Layout.fillHeight: true
                        isPrimary: true
                    }
                }
            }

            CielSeparator {}

            RowLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true
                spacing: 0

                ColumnLayout {
                    id: quickSidebar
                    Layout.fillHeight: true
                    Layout.fillWidth: false
                    Layout.preferredWidth: quickSidebarWidth
                    Layout.margins: 24
                    Layout.alignment: Qt.AlignTop
                    clip: true
                    spacing: 8

                    Text {
                        text: "Quick Access"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        spacing: 4
                        model: placesModel

                        delegate: CielSquircle {
                            id: delegateRoot

                            function locationPath() {
                                switch (location) {
                                case "home":
                                    return AppPaths.home();
                                case "desktop":
                                    return AppPaths.desktop();
                                case "documents":
                                    return AppPaths.documents();
                                case "downloads":
                                    return AppPaths.downloads();
                                case "pictures":
                                    return AppPaths.pictures();
                                case "music":
                                    return AppPaths.music();
                                case "videos":
                                    return AppPaths.videos();
                                case "trash":
                                    return AppPaths.trash();
                                default:
                                    return "";
                                }
                            }
                            width: ListView.view.width
                            height: 36

                            RowLayout {
                                anchors.fill: parent
                                anchors.topMargin: 2
                                anchors.bottomMargin: 2
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                CielIcon {
                                    icon: iconName
                                    size: 20
                                }

                                Text {
                                    text: name
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    color: Theme.textPrimary
                                }

                                Item {
                                    Layout.fillWidth: true
                                }
                            }

                            HoverHandler {
                                id: hoverHandler
                            }

                            color: hoverHandler.hovered || TabManager.currentPath == delegateRoot.locationPath() ? Theme.background : Theme.surface

                            TapHandler {
                                onTapped: TabManager.setCurrentPath(delegateRoot.locationPath())
                            }
                        }
                    }
                }

                CielSeparator {
                    id: separator
                    vertical: true
                    color: (hoverHandlerSep.hovered || dragHandler.active) ? "#212121" : Theme.border
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                    HoverHandler {
                        id: hoverHandlerSep
                        margin: 5
                        cursorShape: Qt.SplitHCursor
                    }

                    DragHandler {
                        id: dragHandler
                        target: null
                        margin: 5
                        xAxis.enabled: true
                        yAxis.enabled: false
                        cursorShape: Qt.SplitHCursor

                        property real startWidth: 0

                        onActiveChanged: {
                            if (active) {
                                startWidth = quickSidebarWidth;
                            }
                        }

                        onTranslationChanged: {
                            if (active) {
                                var targetWidth = startWidth + translation.x;
                                quickSidebarWidth = Math.max(quickSidebarMinWidth, Math.min(quickSidebarMaxWidth, targetWidth));
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 32
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.topMargin: 4
                        Layout.bottomMargin: 5

                        Item {
                            Layout.fillWidth: true
                        }
                        CielIconButton {
                            icon: TabManager.currentSettings.listViewMode ? "squares-four" : "list-dashes"
                            onClicked: TabManager.toggleViewMode()
                        }
                        CielIconButton {
                            id: filterButton
                            icon: "funnel"

                            readonly property int sortDateModified: 0
                            readonly property int sortType: 1
                            readonly property int sortName: 2
                            readonly property int sortSize: 3

                            CielDropDown {
                                id: filterMenu
                                trigger: filterButton
                                placement: "bottom"

                                CielMenuSub {
                                    text: "Sort by"
                                    icon: "arrows-down-up"

                                    CielMenuItem {
                                        text: "Date Modified"
                                        icon: TabManager.currentSettings.sortBy === filterButton.sortDateModified ? "check" : ""
                                        onTriggered: {
                                            TabManager.setSortBy(filterButton.sortDateModified);
                                            filterMenu.close();
                                        }
                                    }

                                    CielMenuItem {
                                        text: "Type"
                                        icon: TabManager.currentSettings.sortBy === filterButton.sortType ? "check" : ""
                                        onTriggered: {
                                            TabManager.setSortBy(filterButton.sortType);
                                            filterMenu.close();
                                        }
                                    }

                                    CielMenuItem {
                                        text: "Name"
                                        icon: TabManager.currentSettings.sortBy === filterButton.sortName ? "check" : ""
                                        onTriggered: {
                                            TabManager.setSortBy(filterButton.sortName);
                                            filterMenu.close();
                                        }
                                    }

                                    CielMenuItem {
                                        text: "Size"
                                        icon: TabManager.currentSettings.sortBy === filterButton.sortSize ? "check" : ""
                                        onTriggered: {
                                            TabManager.setSortBy(filterButton.sortSize);
                                            filterMenu.close();
                                        }
                                    }

                                    CielMenuSeparator {}

                                    CielMenuItem {
                                        text: "Ascending"
                                        icon: TabManager.currentSettings.ascending ? "check" : ""
                                        onTriggered: {
                                            if (!TabManager.currentSettings.ascending)
                                                TabManager.toggleAscending();
                                            filterMenu.close();
                                        }
                                    }

                                    CielMenuItem {
                                        text: "Descending"
                                        icon: !TabManager.currentSettings.ascending ? "check" : ""
                                        onTriggered: {
                                            if (TabManager.currentSettings.ascending)
                                                TabManager.toggleAscending();
                                            filterMenu.close();
                                        }
                                    }
                                }

                                CielMenuSeparator {}

                                CielMenuItem {
                                    text: "Folders First"
                                    icon: TabManager.currentSettings.foldersFirstSorting ? "check" : ""
                                    onTriggered: {
                                        TabManager.toggleFoldersFirst();
                                        filterMenu.close();
                                    }
                                }

                                CielMenuItem {
                                    text: "Show Hidden Files"
                                    icon: TabManager.currentSettings.showHiddenFiles ? "check" : ""
                                    shortcut: "Ctrl+H"
                                    onTriggered: {
                                        TabManager.toggleHiddenFiles();
                                        filterMenu.close();
                                    }
                                }

                                CielMenuItem {
                                    text: "Show Symlinks"
                                    icon: TabManager.currentSettings.showSymlinks ? "check" : ""
                                    onTriggered: {
                                        TabManager.toggleSymlinks();
                                        filterMenu.close();
                                    }
                                }
                            }
                        }
                    }

                    CielSeparator {}

                    ColumnLayout {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        Layout.rightMargin: 16
                        Layout.bottomMargin: 16
                        spacing: 0

                        CielSquircle {
                            id: viewArea
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            color: Theme.transparent
                            focus: true
                            readonly property int columns: TabManager.currentSettings.listViewMode ? 1 : Math.max(1, Math.floor(width / 130))
                            readonly property int rowsPerPage: Math.max(1, Math.floor(height / (TabManager.currentSettings.listViewMode ? 42 : 120)))
                            readonly property int pageSize: rowsPerPage * columns

                            property string typeAheadBuffer: ""

                            Component.onCompleted: forceActiveFocus()
                            Timer {
                                id: typeAheadTimer
                                interval: 800
                                onTriggered: viewArea.typeAheadBuffer = ""
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: function (mouse) {
                                    viewArea.forceActiveFocus();
                                    if (mouse.button === Qt.RightButton) {
                                        fileContextMenu.close();
                                        emptySpaceContextMenu.popup(mouse.x, mouse.y, this);
                                    }
                                }
                            }

                            Connections {
                                target: FileListModel
                                function onFocusedRowChanged() {
                                    if (loader.item && typeof loader.item.positionViewAtIndex === "function") {
                                        loader.item.positionViewAtIndex(FileListModel.focusedRow, ListView.Contain);
                                    }
                                }
                            }
                            Loader {
                                id: loader
                                anchors.fill: parent
                                sourceComponent: TabManager.currentSettings.listViewMode ? listViewComponent : gridViewComponent
                            }

                            Component {
                                id: listViewComponent

                                CielListView {
                                    id: fileList
                                    anchors.fill: parent
                                    anchors.topMargin: 4
                                    anchors.bottomMargin: 4
                                    model: FileListModel
                                    TapHandler {
                                        onTapped: function (eventPoint) {
                                            var p = fileList.mapToItem(fileList.contentItem, eventPoint.position.x, eventPoint.position.y);
                                            if (fileList.indexAt(p.x, p.y) === -1) {
                                                FileListModel.clearSelection();
                                                root.forceActiveFocus();
                                            }
                                        }
                                    }
                                    delegate: Item {
                                        id: fileDelegate
                                        width: fileList.width
                                        height: 42

                                        readonly property bool isFocused: FileListModel.focusedRow === index && viewArea.activeFocus
                                        readonly property bool isSelected: model.selected

                                        CielSquircle {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            anchors.topMargin: 2
                                            anchors.bottomMargin: 2
                                            borderWidth: 2
                                            borderColor: isFocused ? "#64c5fa" : "white"

                                            color: isSelected ? "#b4e2fa" : itemHover.hovered ? Theme.background : Theme.surface

                                            HoverHandler {
                                                id: itemHover
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16
                                                anchors.rightMargin: 16
                                                spacing: 12

                                                CielIcon {
                                                    icon: model.isDir ? "folder" : "file"
                                                }

                                                Text {
                                                    text: model.name
                                                    color: Theme.textPrimary
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: model.isDir ? "" : (model.size + " B")
                                                    color: Theme.textSecondary
                                                    Layout.preferredWidth: 80
                                                }

                                                Text {
                                                    text: model.modified
                                                    color: Theme.textSecondary
                                                    Layout.preferredWidth: 120
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onDoubleClicked: {
                                                if (model.isDir) {
                                                    TabManager.openFolder(model.name);
                                                }
                                            }
                                            onClicked: function (mouse) {
                                                viewArea.forceActiveFocus();
                                                FileListModel.handleSelection(index, mouse.modifiers);
                                            }
                                        }
                                    }
                                }
                            }

                            CielSquircle {
                                id: visualSelectionRect
                                color: "#b4e2fa"
                                borderWidth: 2
                                borderColor: "#64c5fa"
                                opacity: 0.5
                                visible: false
                            }
                            Component {
                                id: gridViewComponent

                                CielGridView {
                                    id: fileGrid
                                    anchors.fill: parent
                                    cellWidth: 130
                                    cellHeight: 120
                                    model: FileListModel
                                    TapHandler {
                                        onTapped: function (eventPoint) {
                                            var p = fileGrid.mapToItem(fileGrid.contentItem, eventPoint.position.x, eventPoint.position.y);
                                            if (fileGrid.indexAt(p.x, p.y) === -1) {
                                                FileListModel.clearSelection();
                                                root.forceActiveFocus();
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        property real startX: 0
                                        property real startY: 0
                                        property bool isDragging: false
                                        readonly property real dragThreshold: 4

                                        preventStealing: isDragging

                                        function updateSelection() {
                                            var selL = visualSelectionRect.x;
                                            var selT = visualSelectionRect.y;
                                            var selR = visualSelectionRect.x + visualSelectionRect.width;
                                            var selB = visualSelectionRect.y + visualSelectionRect.height;

                                            let selectedIndices = [];

                                            for (var i = 0; i < fileGrid.count; ++i) {
                                                var item = fileGrid.itemAtIndex(i);

                                                if (!item || !item.visible)
                                                    continue;

                                                var pos = item.mapToItem(fileGrid, 0, 0);
                                                var itemL = pos.x;
                                                var itemT = pos.y;
                                                var itemR = pos.x + item.width;
                                                var itemB = pos.y + item.height;

                                                // 3. Exact collision test
                                                var intersects = (selL < itemR && selR > itemL && selT < itemB && selB > itemT);

                                                if (intersects) {
                                                    selectedIndices.push(i);
                                                }
                                            }

                                            var lastIndex = selectedIndices.length > 0 ? selectedIndices[selectedIndices.length - 1] : -1;
                                            FileListModel.setSelection(selectedIndices);
                                        }

                                        onPressed: mouse => {
                                            var contentPoint = fileGrid.mapToItem(fileGrid.contentItem, mouse.x, mouse.y);
                                            var hitIndex = fileGrid.indexAt(contentPoint.x, contentPoint.y);
                                            if (hitIndex !== -1) {
                                                mouse.accepted = false;
                                                return;
                                            }
                                            startX = mouse.x;
                                            startY = mouse.y;
                                            isDragging = false;
                                            viewArea.forceActiveFocus();
                                        }

                                        onPositionChanged: mouse => {
                                            if (!pressed)
                                                return;
                                            var dx = mouse.x - startX;
                                            var dy = mouse.y - startY;

                                            if (!isDragging && (Math.abs(dx) > dragThreshold || Math.abs(dy) > dragThreshold)) {
                                                isDragging = true;
                                                visualSelectionRect.visible = true;
                                            }

                                            if (isDragging) {
                                                visualSelectionRect.x = Math.min(mouse.x, startX);
                                                visualSelectionRect.y = Math.min(mouse.y, startY);
                                                visualSelectionRect.width = Math.abs(mouse.x - startX);
                                                visualSelectionRect.height = Math.abs(mouse.y - startY);

                                                updateSelection();
                                            }
                                        }

                                        onReleased: {
                                            if (isDragging) {
                                                visualSelectionRect.visible = false;
                                                isDragging = false;
                                            } else {
                                                FileListModel.clearSelection();
                                            }
                                        }

                                        onCanceled: {
                                            visualSelectionRect.visible = false;
                                            isDragging = false;
                                        }
                                    }
                                    delegate: Item {
                                        id: gridDelegate
                                        width: fileGrid.cellWidth
                                        height: fileGrid.cellHeight
                                        readonly property bool isFocused: FileListModel.focusedRow === index && viewArea.activeFocus
                                        readonly property bool isSelected: model.selected

                                        CielSquircle {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            color: isSelected ? "#b4e2fa" : gridHover.hovered ? Theme.background : Theme.surface
                                            borderWidth: 2
                                            borderColor: isFocused ? "#64c5fa" : "white"

                                            HoverHandler {
                                                id: gridHover
                                            }

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                spacing: 4
                                                Item {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 68
                                                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

                                                    Image {
                                                        id: thumbnailImage
                                                        visible: !model.isDir && thumbnailImage.status === Image.Ready
                                                        anchors.fill: parent
                                                        source: "image://thumbnail/" + TabManager.currentPath + "/" + model.name
                                                        sourceSize.width: 280
                                                        fillMode: Image.PreserveAspectFit
                                                        asynchronous: true
                                                    }
                                                    FileIcon {
                                                        visible: !model.isDir && thumbnailImage.status === Image.Error
                                                        anchors.centerIn: parent
                                                    }

                                                    FolderIcon {
                                                        visible: model.isDir && thumbnailImage.status === Image.Error
                                                        anchors.centerIn: parent
                                                    }
                                                }
                                                Item {
                                                    Layout.fillHeight: true
                                                }
                                                Text {
                                                    text: model.name
                                                    color: Theme.textPrimary
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideMiddle
                                                    maximumLineCount: 2
                                                }

                                                Item {
                                                    Layout.fillHeight: true
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton

                                            onDoubleClicked: function (mouse) {
                                                if (mouse.button === Qt.LeftButton && model.isDir) {
                                                    TabManager.openFolder(model.name);
                                                }
                                            }

                                            onClicked: function (mouse) {
                                                viewArea.forceActiveFocus();

                                                if (mouse.button === Qt.LeftButton) {
                                                    FileListModel.handleSelection(index, mouse.modifiers);
                                                } else if (mouse.button === Qt.RightButton) {
                                                    if (!model.selected) {
                                                        FileListModel.handleSelection(index, 0);
                                                    }
                                                    emptySpaceContextMenu.close();
                                                    fileContextMenu.popup(mouse.x, mouse.y, this);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    CielPopup {
        id: createFolderPopup

        contentWidth: 400
        contentHeight: 165
        onOpened: {
            Qt.callLater(function () {
                newFolderNameInput.inputField.forceActiveFocus();
            });
        }

        onClosed: {
            newFolderNameInput.text = "";
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: "Folder Name"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }

                CielInput {
                    id: newFolderNameInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    placeholder: "folderName"
                    isPrimary: true
                    onAccepted: {
                        FileListModel.createFolder(newFolderNameInput.text);
                        createFolderPopup.close();
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight
                spacing: 8
                CielButton {
                    text: "Cancel"
                    onClicked: {
                        createFolderPopup.close();
                    }
                }
                CielButton {
                    Layout.alignment: Qt.AlignRight
                    text: "Create"
                    primary: true
                    onClicked: {
                        FileListModel.createFolder(newFolderNameInput.text);
                        createFolderPopup.close();
                    }
                }
            }
        }
    }
    CielContextMenu {
        id: emptySpaceContextMenu

        CielMenuItem {
            text: "Open Terminal Here"
            onTriggered: {
                TabManager.addSelectedToClipboard();
                emptySpaceContextMenu.close();
            }
        }
        CielMenuSeparator {}
        CielMenuItem {
            text: "Paste"
            shortcut: "Ctrl+V"
            onTriggered: {
                emptySpaceContextMenu.close();
                TabManager.paste();
            }
        }
        CielMenuItem {
            text: "Copy Path"
            shortcut: "Ctrl+Shift+C"
            onTriggered: {
                TabManager.setClipboardText(TabManager.currentPath);
                emptySpaceContextMenu.close();
            }
        }
        CielMenuSeparator {}
        CielMenuItem {
            text: "Bookmark"
            icon: "bookmark"
            shortcut: "Ctrl+B"
            onTriggered: {
                emptySpaceContextMenu.close();
            }
        }
        CielMenuSub {
            text: "Create "
            icon: "plus"
            CielMenuItem {
                text: "Create File"
                icon: "file"
                onTriggered: {
                    emptySpaceContextMenu.close();
                    createFilePopup.open();
                }
            }
            CielMenuItem {
                text: "Create Folder"
                icon: "folder"
                onTriggered: {
                    emptySpaceContextMenu.close();
                    createFolderPopup.open();
                }
            }
        }
        CielMenuSeparator {}
        CielMenuItem {
            text: "Properties"
            icon: "info"
            shortcut: "Alt+Enter"
            onTriggered: {
                emptySpaceContextMenu.close();
            }
        }
    }

    CielContextMenu {
        id: fileContextMenu
        property bool bookmarkBtn: true

        CielMenuItem {
            text: "Duplicate"
            shortcut: "Ctrl+D"
            onTriggered: {
                fileContextMenu.close();
                TabManager.addSelectedToClipboard();
                TabManager.paste();
            }
        }
        CielMenuItem {
            text: "Copy Path"
            shortcut: "Ctrl+Shift+C"
            onTriggered: {
                fileContextMenu.close();
            }
        }
        CielMenuItem {
            text: "Paste"
            shortcut: "Ctrl+V"
            onTriggered: {
                fileContextMenu.close();
                TabManager.paste();
            }
        }
        CielMenuSeparator {}

        CielMenuItem {
            text: "Cut"
            icon: "scissors"
            shortcut: "Ctrl+X"
            onTriggered: {
                TabManager.setCutMode(true);
                TabManager.addSelectedToClipboard();
                fileContextMenu.close();
            }
        }
        CielMenuItem {
            text: "Copy"
            icon: "copy"
            shortcut: "Ctrl+C"
            onTriggered: {
                TabManager.addSelectedToClipboard();
                fileContextMenu.close();
            }
        }
        CielMenuSeparator {}

        CielMenuItem {
            text: "Rename"
            icon: "pencil"
            shortcut: "F2"
            onTriggered: {
                fileContextMenu.close();
            }
        }
        CielMenuItem {
            visible: fileContextMenu.bookmarkBtn
            text: "Bookmark"
            icon: "bookmark"
            shortcut: "Ctrl+B"
            onTriggered: {
                fileContextMenu.close();
            }
        }
        CielMenuItem {
            text: "Compress"
            icon: "file-archive"
            shortcut: "Ctrl+Shift+Z"
            onTriggered: {
                fileContextMenu.close();
            }
        }
        CielMenuSeparator {}

        CielMenuItem {
            text: "Properties"
            icon: "info"
            shortcut: "Alt+Enter"
            onTriggered: {
                fileContextMenu.close();
            }
        }
        CielMenuSeparator {}

        CielMenuItem {
            text: "Delete"
            icon: "trash"
            destructive: true
            shortcut: "Delete"
            onTriggered: {
                fileContextMenu.close();
            }
        }
    }

    CielPopup {
        id: transferPopup
        contentWidth: 440
        contentHeight: contentLayout.implicitHeight + 40

        property string currentFile: ""
        property real progress: 0.0
        property string conflictFile: ""
        readonly property bool hasConflict: conflictFile.length > 0

        Behavior on contentHeight {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.margins: 20
            spacing: 0

            ColumnLayout {
                visible: !transferPopup.hasConflict
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Copying " + transferPopup.currentFile
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }

                    Text {
                        text: Math.round(transferPopup.progress * 100) + "%"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                ProgressBar {
                    value: transferPopup.progress
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    CielButton {
                        text: "Cancel"
                        onClicked: {
                            TabManager.cancelOperation();
                            transferPopup.close();
                        }
                    }
                }
            }

            ColumnLayout {
                visible: transferPopup.hasConflict
                Layout.fillWidth: true
                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "File Already Exists"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "\"" + transferPopup.conflictFile + "\" already exists in this destination."
                        color: Theme.textSecondary
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    CielInput {
                        id: renameField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        placeholder: "New file name"
                        text: transferPopup.conflictFile
                        focus: transferPopup.hasConflict

                        onAccepted: {
                            if (renameField.text.trim().length > 0) {
                                var newName = renameField.text.trim();
                                transferPopup.conflictFile = "";
                                TabManager.resolveConflict(2, applyAllCheck.checked, newName);
                            }
                        }
                    }

                    CielButton {
                        text: "Rename"
                        enabled: renameField.text.trim().length > 0 && renameField.text !== transferPopup.conflictFile
                        onClicked: {
                            var newName = renameField.text.trim();
                            transferPopup.conflictFile = "";
                            TabManager.resolveConflict(2, applyAllCheck.checked, newName);
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    CielCheckBox {
                        id: applyAllCheck
                        text: "Apply to all"
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    CielButton {
                        text: "Cancel"
                        onClicked: {
                            TabManager.cancelOperation();
                            transferPopup.conflictFile = "";
                            transferPopup.close();
                        }
                    }

                    CielButton {
                        text: "Skip"
                        onClicked: {
                            transferPopup.conflictFile = "";
                            TabManager.resolveConflict(0, applyAllCheck.checked);
                        }
                    }

                    CielButton {
                        text: "Overwrite"
                        primary: true
                        onClicked: {
                            transferPopup.conflictFile = "";
                            TabManager.resolveConflict(1, applyAllCheck.checked);
                        }
                    }
                }
            }
        }
    }
    CielPopup {
        id: pathErrorPopup

        property string title: ""
        property string message: ""

        contentWidth: 400
        contentHeight: 180

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: pathErrorPopup.title
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: pathErrorPopup.message
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            Item {
                Layout.fillHeight: true
            }

            CielButton {
                Layout.alignment: Qt.AlignRight
                text: "OK"
                onClicked: pathErrorPopup.close()
            }
        }
    }
    CielPopup {
        id: createFilePopup

        contentWidth: 400
        contentHeight: 180

        onOpened: {
            fileCreatedName.forceActiveFocus();
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "File Name"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }

                CielInput {
                    id: fileCreatedName
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    isPrimary: true
                    text: "file.txt"
                    placeholder: "file name"
                }
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                }
                CielButton {
                    Layout.alignment: Qt.AlignRight
                    text: "Cancel"
                    onClicked: {
                        createFilePopup.close();
                    }
                }
                CielButton {
                    Layout.alignment: Qt.AlignRight
                    text: "Create"
                    primary: true
                    onClicked: {
                        // permanent delete
                        TabManager.createFile(fileCreatedName.text);
                        createFilePopup.close();
                    }
                }
            }
        }
    }
    CielPopup {
        id: permDeletePopup

        contentWidth: 400
        contentHeight: 180

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Delete Permanently!"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: "This action is not reversable!"
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                }
                CielButton {
                    Layout.alignment: Qt.AlignRight
                    text: "Cancel"
                    onClicked: {
                        permDeletePopup.close();
                    }
                }
                CielButton {
                    Layout.alignment: Qt.AlignRight
                    text: "OK"
                    primary: true
                    onClicked: {
                        // permanent delete
                        TabManager.deleteSelected(true);
                        permDeletePopup.close();
                    }
                }
            }
        }
    }
}
