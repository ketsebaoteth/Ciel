import QtQuick
import QtQuick.Layouts
import QtWebEngine
import Ciel.Ui
import Ciel.Browser 1.0
import "../window"

Item {
    id: root

    property bool collapsed: false
    property var activeView: null
    required property BrowserConfig config
    property var browserSettings: null
    signal collapseToggled

    clip: true
    implicitHeight: collapsed ? 116 : 94

    property real bloomProgress: collapsed ? 1.0 : 0.0

    property bool isPrivate: false
    signal sitePermissionsRequested

    readonly property string siteOrigin: {
        var u = (root.activeView && root.activeView.url) ? root.activeView.url.toString() : "";
        return /^https?:\/\//.test(u) ? SitePermissionManager.originOf(root.activeView.url) : "";
    }
    readonly property bool permissionsAvailable: siteOrigin !== "" && !isPrivate

    property int permRevision: 0
    property bool permChanged: false
    property var shownKeys: []

    property var webProfile: null
    property var extensionList: []
    property string extPopupUrl: ""

    function refreshExtensions() {
        root.extensionList = ExtensionManager.list().filter(function (e) {
            return e.enabled && e.popupUrl !== "" && e.error === ""
        })
    }

    function openExtensionPopup(ext) {
        var url = ext.popupUrl
        extensionMenu.trigger = null
        permissionsMenu.close()
        extensionMenu.close()
        root.extPopupUrl = ""
        Qt.callLater(function () {
            extensionMenu.trigger = extPopupAnchor
            root.extPopupUrl = url
            extensionMenu.open()
        })
    }

    Connections {
        target: ExtensionManager
        function onExtensionsChanged() { root.refreshExtensions() }
    }

    Connections {
        target: extensionMenu
        ignoreUnknownSignals: true
        function onClosed() {
            root.extPopupUrl = ""
            extensionMenu.trigger = null
        }
    }

    readonly property var permFeatures: [
        {
            key: "microphone",
            name: "Microphone",
            icon: "microphone"
        },
        {
            key: "camera",
            name: "Camera",
            icon: "camera"
        },
        {
            key: "location",
            name: "Location",
            icon: "map-pin"
        },
        {
            key: "notifications",
            name: "Notifications",
            icon: "bell"
        }
    ]

    function permState(key) {
        root.permRevision;
        return root.siteOrigin !== "" ? SitePermissionManager.permissionState(root.siteOrigin, key) : "";
    }

    function setPerm(key, state) {
        if (root.siteOrigin === "")
            return;
        SitePermissionManager.setPermission(root.siteOrigin, key, state);
        root.permChanged = true;
    }

    function openSiteControls(btn) {
        root.refreshExtensions();
        extensionMenu.trigger = null
        extensionMenu.close()
        root.extPopupUrl = ""

        var wasOpen = permissionsMenu.isOpen;

        root.permChanged = false;

        var keys = [];
        for (var i = 0; i < root.permFeatures.length; ++i) {
            var k = root.permFeatures[i].key;
            if (SitePermissionManager.permissionState(root.siteOrigin, k) !== "")
                keys.push(k);
        }

        root.shownKeys = keys;

        permissionsMenu.trigger = null;

        Qt.callLater(function () {
            permissionsMenu.trigger = btn;

            if (wasOpen)
                permissionsMenu.close();
            else
                permissionsMenu.open();
        });
    }

    Connections {
        target: SitePermissionManager
        function onPermissionsChanged() {
            root.permRevision++;
        }
    }

    function cleanDisplayUrl(raw) {
        if (!raw || raw === "about:blank" || raw === "")
            return "";
        if (raw.startsWith("ciel://") || raw.startsWith("about:"))
            return raw;
        var s = raw.replace(/^[a-zA-Z]+:\/\//, "");
        s = s.replace(/^www\./, "");
        var slash = s.indexOf("/");
        return slash !== -1 ? s.substring(0, slash) : s;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
        z: -1
    }

    Behavior on implicitHeight {
        CielSpring {
            damping: 3.0
            spring: 10.2
            mass: 3.2
            epsilon: 0.002
        }
    }

    Behavior on bloomProgress {
        CielSpring {
            damping: 4.5
            spring: 6.0
            mass: 3.5
            epsilon: 0.005
        }
    }

    TextEdit {
        id: clipHelper
        visible: false
    }

    Item {
        id: bloomExpandedDeck
        anchors.fill: parent
        visible: opacity > 0.0
        opacity: Math.max(0.0, 1.0 - root.bloomProgress * 2.0)
        scale: 1.0 - (root.bloomProgress * 0.10)
        transformOrigin: Item.Center

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                CielIconButton {
                    icon: "arrow-left"
                    size: Theme.SMALL
                    opacity: root.activeView && root.activeView.canGoBack ? 1.0 : 0.35
                    onClicked: {
                        if (root.activeView && root.activeView.canGoBack)
                            root.activeView.goBack();
                    }
                }

                CielIconButton {
                    icon: "arrow-right"
                    size: Theme.SMALL
                    opacity: root.activeView && root.activeView.canGoForward ? 1.0 : 0.35
                    onClicked: {
                        if (root.activeView && root.activeView.canGoForward)
                            root.activeView.goForward();
                    }
                }

                CielIconButton {
                    icon: root.activeView && root.activeView.loading ? "x" : "arrow-clockwise"
                    size: Theme.SMALL
                    onClicked: {
                        if (!root.activeView)
                            return;
                        if (root.activeView.loading)
                            root.activeView.stop();
                        else
                            root.activeView.reload();
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                CielIconButton {
                    icon: "sidebar-simple"
                    size: Theme.SMALL
                    onClicked: root.collapseToggled()
                }
            }

            CielSearch {
                id: omniboxVertical
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                placeholder: "Search or enter URL"

                readonly property string fullUrlStr: (root.activeView && root.activeView.url) ? root.activeView.url.toString() : ""

                text: {
                    if (omniboxVertical.isInputActive) {
                        return fullUrlStr === "about:blank" ? "" : fullUrlStr;
                    }
                    return root.cleanDisplayUrl(fullUrlStr);
                }

                onAccepted: query => {
                    if (root.activeView) {
                        root.activeView.url = root.config.resolveQueryOrUrl(omniGhost.completed(query));
                        omniboxVertical.inputField.focus = false;
                    }
                }

                Keys.onPressed: event => omniGhost.handleKey(event)

                preContent: CielIconButton {
                    id: linkBtnVertical
                    property bool copied: false
                    icon: copied ? "check" : "link"
                    size: Theme.XSMALL
                    iconColor: copied ? Theme.accent : Theme.textSecondary

                    Timer {
                        id: copyResetTimerVertical
                        interval: 1500
                        onTriggered: linkBtnVertical.copied = false
                    }

                    onClicked: {
                        if (root.activeView && root.activeView.url) {
                            clipHelper.text = root.activeView.url.toString();
                            clipHelper.selectAll();
                            clipHelper.copy();
                            linkBtnVertical.copied = true;
                            copyResetTimerVertical.restart();
                        }
                    }
                }

                postContent: RowLayout {
                    spacing: 2

                    CielIconButton {
                        id: starBtn

                        property int revision: 0

                        readonly property bool bookmarked: {
                            starBtn.revision;
                            return (root.activeView && root.activeView.url) ? ProfileManager.isBookmarked(root.activeView.url.toString()) : false;
                        }

                        icon: bookmarked ? "star-fill" : "star"
                        size: Theme.XSMALL
                        iconColor: bookmarked ? Theme.accent : Theme.textSecondary

                        Connections {
                            target: ProfileManager
                            function onBookmarksChanged() {
                                starBtn.revision++;
                            }
                        }

                        onClicked: {
                            if (root.activeView && root.activeView.url) {
                                var u = root.activeView.url.toString();
                                var t = root.activeView.title ? root.activeView.title : u;
                                ProfileManager.toggleBookmark(u, t);
                            }
                        }
                    }

                    CielIconButton {
                        id: siteControlsBtn
                        icon: "faders-horizontal"
                        size: Theme.XSMALL
                        enabled: root.permissionsAvailable
                        opacity: enabled ? 1.0 : 0.35
                        iconColor: permissionsMenu.opened ? Theme.accent : Theme.textSecondary
                        onClicked: root.openSiteControls(siteControlsBtn)

                        Item {
                            id: extPopupAnchor
                            anchors.centerIn: parent
                            width: 1
                            height: 1
                        }
                    }
                }
            }
        }

        UrlGhostText {
            id: omniGhost
            target: omniboxVertical
            active: omniboxVertical.isInputActive
        }
    }

    Item {
        id: bloomCollapsedSpine
        anchors.fill: parent
        visible: opacity > 0.0
        opacity: Math.max(0.0, (root.bloomProgress - 0.3) * 1.42)
        scale: 0.90 + (root.bloomProgress * 0.10)
        transformOrigin: Item.Center

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            spacing: 4

            CielIconButton {
                Layout.alignment: Qt.AlignHCenter
                icon: "sidebar-simple"
                size: Theme.SMALL
                onClicked: root.collapseToggled()
            }

            CielIconButton {
                Layout.alignment: Qt.AlignHCenter
                icon: "magnifying-glass"
                size: Theme.SMALL
                onClicked: root.collapseToggled()
            }

            CielIconButton {
                Layout.alignment: Qt.AlignHCenter
                icon: root.activeView && root.activeView.loading ? "x" : "arrow-clockwise"
                size: Theme.SMALL
                onClicked: {
                    if (!root.activeView)
                        return;
                    if (root.activeView.loading)
                        root.activeView.stop();
                    else
                        root.activeView.reload();
                }
            }
        }
    }

    CielDropDown {
        id: permissionsMenu
        placement: "bottom"

        Item {
            implicitWidth: permCol.implicitWidth
            implicitHeight: permCol.implicitHeight + 24

            ColumnLayout {
                id: permCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                Text {
                    text: "Site permissions"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Theme.textSecondary
                }

                Text {
                    text: root.siteOrigin.replace(/^https?:\/\//, "")
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Repeater {
                    model: root.permFeatures.filter(function (f) {
                        return root.shownKeys.indexOf(f.key) >= 0;
                    })

                    delegate: RowLayout {
                        id: permRow
                        Layout.fillWidth: true
                        spacing: 8

                        readonly property string st: root.permState(modelData.key)

                        CielIcon {
                            icon: modelData.icon
                            size: Theme.XSMALL
                            color: permRow.st === "granted" ? Theme.accent : (permRow.st === "denied" ? "#EF4444" : Theme.textSecondary)
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: modelData.name
                            font.pixelSize: 13
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Item {
                            width: 30
                        }

                        CielButton {
                            text: "Ask"
                            primary: permRow.st === "ask" || permRow.st === ""
                            onClicked: root.setPerm(modelData.key, "ask")
                        }
                        CielButton {
                            text: "Allow"
                            primary: permRow.st === "granted"
                            onClicked: root.setPerm(modelData.key, "granted")
                        }
                        CielButton {
                            text: "Block"
                            primary: permRow.st === "denied"
                            onClicked: root.setPerm(modelData.key, "denied")
                        }
                    }
                }

                Text {
                    visible: root.shownKeys.length === 0
                    text: "This site hasn't asked for any permissions yet."
                    font.pixelSize: 12
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 3
                    color: Theme.surface
                }

                Text {
                    text: "Extensions"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Theme.textSecondary
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.extensionList.length > 0

                    Repeater {
                        model: root.extensionList

                        delegate: Item {
                            width: 36
                            height: 36

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: Theme.textPrimary
                                opacity: extMouse.containsMouse ? 0.08 : 0.0
                            }

                            Image {
                                id: extIcon
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                source: modelData.iconUrl
                                sourceSize.width: 40
                                sourceSize.height: 40
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                            }
                            CielIcon {
                                anchors.centerIn: parent
                                icon: "puzzle-piece"
                                size: Theme.XSMALL
                                color: Theme.textSecondary
                                visible: !extIcon.visible
                            }

                            MouseArea {
                                id: extMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openExtensionPopup(modelData)
                            }
                        }
                    }
                }

                Text {
                    visible: root.extensionList.length === 0
                    text: "No enabled extensions with a popup."
                    font.pixelSize: 12
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                }
            }
        }
    }

    CielDropDown {
        id: extensionMenu
        placement: "bottom"

        Item {
            id: extBox
            clip: true
            implicitWidth: 380
            implicitHeight: 520

            Loader {
                id: extLoader
                anchors.fill: parent
                active: extensionMenu.opened && root.extPopupUrl !== ""

                sourceComponent: WebEngineView {
                    id: extView
                    profile: root.webProfile ? root.webProfile
                             : (root.activeView ? root.activeView.profile : null)
                    backgroundColor: "transparent"
                    settings.javascriptEnabled: true
                    settings.localStorageEnabled: true
                    settings.autoLoadImages: true

                    Component.onCompleted: {
                        if (root.extPopupUrl !== "")
                            url = root.extPopupUrl
                    }

                    onJavaScriptConsoleMessage: (level, message, line, source) =>
                        console.log("[ext-popup]", message, source + ":" + line)

                    onLoadingChanged: info => {
                        if (info.status === WebEngineLoadingInfo.LoadFailedStatus)
                            console.warn("[ext-popup] load failed:", info.url, info.errorString)
                    }
                }
            }
        }
    }
}
