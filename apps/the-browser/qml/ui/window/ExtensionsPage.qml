import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Ciel.Ui
import Ciel.Browser 1.0

Item {
    id: root

    property string errorText: ""

    ListModel {
        id: extModel
    }

    signal openTabRequested(string url)

    function openExtensionPage(u) { root.openTabRequested(u) }

    function reloadExtensions() {
        var items = ExtensionManager.list();
        extModel.clear();
        for (var i = 0; i < items.length; ++i)
            extModel.append(items[i]);
    }

    Component.onCompleted: reloadExtensions()
    onVisibleChanged: if (visible)
        reloadExtensions()

    FolderDialog {
        id: folderDialog
        title: "Select an unpacked extension folder"
        onAccepted: ExtensionManager.installFromFolder(selectedFolder.toString())
    }

    Connections {
        target: ExtensionManager
        function onInstallFailed(message) { root.errorText = message }
        function onInstallSucceeded() { root.errorText = "" }
        function onExtensionsChanged() {
            if (root.visible && !extList.busyClosing)
                root.reloadExtensions()
        }
    }
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 32
        anchors.bottomMargin: 24
        width: Math.min(740, parent.width - 64)

        CielFocusWrapper {
            anchors.fill: parent

            ColumnLayout {
                anchors.fill: parent
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: "Extensions"
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    CielButton {
                        text: "Load unpacked…"
                        primary: true
                        onClicked: {
                            root.errorText = "";
                            folderDialog.open();
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    CielSearch {
                        id: storeField
                        Layout.preferredWidth: 400
                        Layout.preferredHeight: 32
                        placeholder: "Chrome Web Store URL or extension ID"
                        showBorder: true
                        preContent: Item {}
                        postContent: Item {}
                        onAccepted: query => {
                            root.errorText = ""
                            ExtensionManager.installFromStore(query)
                        }
                    }

		    Item {
			Layout.fillWidth: true
		    }

                    CielButton {
                        text: ExtensionManager.busy ? "Installing…" : "Install"
                        primary: !ExtensionManager.busy && storeField.text !== ""
                        enabled: !ExtensionManager.busy && storeField.text !== ""
                        onClicked: {
                            root.errorText = ""
                            ExtensionManager.installFromStore(storeField.text)
                        }
                    }
                }

                Text {
                    text: "Loads unpacked Chrome extensions (Manifest V3 preferred). Support depends on the "
                          + "Chromium APIs that Qt WebEngine exposes. Extensions don't run in private windows."
                    font.pixelSize: 12
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.errorText !== ""
                    text: root.errorText
                    font.pixelSize: 12
                    color: "#EF4444"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Item {
                        anchors.centerIn: parent
                        visible: extModel.count === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            CielIcon {
                                icon: "puzzle-piece"
                                size: Theme.MEDIUM
                                color: Theme.textSecondary
                                opacity: 0.35
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: "No extensions installed. Choose \"Load unpacked…\" and pick a folder with a manifest.json."
                                font.pixelSize: 13
                                color: Theme.textSecondary
                                opacity: 0.8
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    CielScrollView {
                        anchors.fill: parent
                        visible: extModel.count > 0

                        ListView {
                            id: extList
                            anchors.fill: parent
                            spacing: 6
                            clip: true
                            model: extModel

                            property bool busyClosing: false

                            delegate: Item {
                                id: extDelegate
                                width: extList.width
                                height: Math.max(0, 84 * closeDimension)

                                property real closeScale: 1.0
                                property real closeOpacity: 1.0
                                property real closeDimension: 1.0
                                property bool isClosing: false

                                function requestClose() {
                                    if (isClosing)
                                        return;
                                    isClosing = true;
                                    extList.busyClosing = true;
                                    closeAnimation.restart();
                                }

                                ParallelAnimation {
                                    id: closeAnimation
                                    NumberAnimation {
                                        target: extDelegate
                                        property: "closeScale"
                                        to: 0.2
                                        duration: 200
                                        easing.type: Easing.InQuad
                                    }
                                    SequentialAnimation {
                                        PauseAnimation {
                                            duration: 45
                                        }
                                        NumberAnimation {
                                            target: extDelegate
                                            property: "closeDimension"
                                            to: 0.0
                                            duration: 175
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                    NumberAnimation {
                                        target: extDelegate
                                        property: "closeOpacity"
                                        to: 0.0
                                        duration: 180
                                        easing.type: Easing.OutQuad
                                    }
                                    onFinished: {
                                        var id = model.id;
                                        extModel.remove(index);
                                        ExtensionManager.remove(id);
                                        extList.busyClosing = false;
                                    }
                                }

                                Item {
                                    id: content
                                    anchors.fill: parent
                                    opacity: extDelegate.isClosing ? extDelegate.closeOpacity : (model.enabled ? 1.0 : 0.6)
                                    transform: Scale {
                                        origin.x: content.width / 2
                                        origin.y: content.height / 2
                                        xScale: extDelegate.isClosing ? extDelegate.closeScale : 1.0
                                        yScale: extDelegate.isClosing ? extDelegate.closeScale : 1.0
                                    }

                                    CielSquircle {
                                        anchors.fill: parent
                                        color: Theme.surface
                                        borderWidth: 1
                                        borderColor: Theme.border
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 10
                                        spacing: 12

                                        Item {
                                            Layout.preferredWidth: 36
                                            Layout.preferredHeight: 36
                                            Layout.alignment: Qt.AlignVCenter

                                            Image {
                                                id: extIcon
                                                anchors.fill: parent
                                                source: model.iconUrl
                                                sourceSize.width: 72
                                                sourceSize.height: 72
                                                fillMode: Image.PreserveAspectFit
                                                visible: status === Image.Ready
                                            }
                                            CielIcon {
                                                anchors.centerIn: parent
                                                icon: "puzzle-piece"
                                                size: Theme.MEDIUM
                                                color: Theme.textSecondary
                                                visible: !extIcon.visible
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Layout.alignment: Qt.AlignVCenter

                                            RowLayout {
                                                spacing: 6
                                                Text {
                                                    text: model.name
                                                    font.pixelSize: 13
                                                    font.weight: Font.Medium
                                                    color: Theme.textPrimary
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: model.version !== "" ? "v" + model.version : ""
                                                    font.pixelSize: 11
                                                    color: Theme.textSecondary
                                                }
                                            }

                                            Text {
                                                text: model.error !== "" ? model.error : model.description
                                                visible: text !== ""
                                                font.pixelSize: 11
                                                color: model.error !== "" ? "#EF4444" : Theme.textSecondary
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: model.runsOn !== "" ? "Runs on: " + model.runsOn : ""
                                                visible: text !== ""
                                                font.pixelSize: 11
                                                color: Theme.textSecondary
                                                opacity: 0.8
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        // CielButton {
                                        //     visible: model.popupUrl !== "" && model.enabled
                                        //     text: "Open"
                                        //     primary: false
                                        //     Layout.alignment: Qt.AlignVCenter
                                        //     onClicked: root.openExtensionPage(model.popupUrl)
                                        // }

                                        CielButton {
                                            text: model.enabled ? "Disable" : "Enable"
                                            primary: !model.enabled
                                            enabled: model.error === ""
                                            Layout.alignment: Qt.AlignVCenter
                                            onClicked: ExtensionManager.setEnabled(model.id, !model.enabled)
                                        }

                                        CielIconButton {
                                            icon: "trash"
                                            Layout.alignment: Qt.AlignVCenter
                                            onClicked: extDelegate.requestClose()
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
