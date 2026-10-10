import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine
import QtQuick.Effects
import Ciel.Ui
import Ciel.Browser 1.0

import "ui/tabs"
import "ui/startpage"
import "ui/history"

ApplicationWindow {
    id: window
    width: 1040
    height: 680
    minimumWidth: 640
    minimumHeight: 460
    visible: true
    title: "Browser"

    color: Theme.background
    property int railOrientation: Qt.Vertical

    property var profileCache: ({})

    function getOrCreateProfile(profileId) {
        if (profileCache[profileId])
            return profileCache[profileId]

        var storage = ProfileManager.webEngineStoragePathFor(profileId)
        var cache   = storage + "/cache"

        var qml = `
            import QtWebEngine
            WebEngineProfile {
                storageName: "ciel-${profileId}"
                offTheRecord: false
                persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
                persistentStoragePath: "${storage}"
                cachePath: "${cache}"
                httpCacheType: WebEngineProfile.DiskHttpCache

                onDownloadRequested: function(download) {
                    var urlStr = download.url ? download.url.toString() : ""
                    if (urlStr.startsWith("blob:") || urlStr.startsWith("data:")) {
                        download.accept()
                    } else {
                        download.cancel()
                        browserConfig.startDownload(download.url, download.downloadFileName, download.mimeType)
                        tabRail.downloadsPopup.open()
                    }
                }
            }`

        var p = Qt.createQmlObject(qml, window, "profile-" + profileId)
        profileCache[profileId] = p
        return p
    }

    readonly property var currentWebProfile: getOrCreateProfile(ProfileManager.activeProfileId)

    Behavior on color {
        enabled: Theme.transitionMs > 0
        ColorAnimation {
            duration: Theme.transitionMs
            easing.type: Easing.OutCubic
        }
    }

    BrowserConfig {
        id: browserConfig
    }

    WorkspaceModel {
        id: workspaceModel
    }

    TabBar {
        id: tabRail
        workspaceModel: workspaceModel
        getWorkspaceViews: idx => webContainer.getWorkspaceViews(idx)
        config: browserConfig
        activeView: webContainer.currentActiveView
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.right: window.railOrientation === Qt.Horizontal ? parent.right : undefined
        anchors.bottom: window.railOrientation === Qt.Vertical ? parent.bottom : undefined
        z: 10
        onHistoryRequested: {
            var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId)
            if (model) model.addTab("ciel://history")
        }
        onProfilesRequested: {
            var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId)
            if (model) model.addTab("ciel://profiles")
        }
        onNewTabRequested: {
            var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId)
            if (model) model.addTab()
        }
    }

    Rectangle {
        id: railDivider
        color: Theme.border
        z: 9
        anchors.left: window.railOrientation === Qt.Vertical ? tabRail.right : parent.left
        anchors.right: window.railOrientation === Qt.Vertical ? undefined : parent.right
        anchors.top: window.railOrientation === Qt.Vertical ? parent.top : tabRail.bottom
        anchors.bottom: window.railOrientation === Qt.Vertical ? parent.bottom : undefined
        width: window.railOrientation === Qt.Vertical ? 1 : parent.width
        height: window.railOrientation === Qt.Vertical ? parent.height : 1
    }

    Item {
        id: webContainer
        anchors.left: window.railOrientation === Qt.Vertical ? railDivider.right : parent.left
        anchors.right: parent.right
        anchors.top: window.railOrientation === Qt.Vertical ? parent.top : railDivider.bottom
        anchors.bottom: parent.bottom
        clip: true

        property real animatedWorkspaceIndex: workspaceModel.currentIndex
        Behavior on animatedWorkspaceIndex {
            CielSpring {
                damping: 0.44
                spring: 3.8
                mass: 1.0
                epsilon: 0.001
            }
        }

        function getWorkspaceViews(idx) {
            var item = workspaceRepeater.itemAt(idx)
            return item ? item.viewRepeater : null
        }

        property var currentActiveView: null
        readonly property var activeTabModel: workspaceModel.tabModel(workspaceModel.currentWorkspaceId)

        property real animatedBackProgress: navFilter.backProgress
        property real animatedForwardProgress: navFilter.forwardProgress

        Behavior on animatedBackProgress {
            enabled: !navFilter.active
            CielSpring { damping: 0.32; spring: 5.2; mass: 1.0; epsilon: 0.001 }
        }
        Behavior on animatedForwardProgress {
            enabled: !navFilter.active
            CielSpring { damping: 0.32; spring: 5.2; mass: 1.0; epsilon: 0.001 }
        }

        SwipeGestureFilter {
            id: navFilter
            anchors.fill: parent
            canGoBack: webContainer.currentActiveView ? webContainer.currentActiveView.canGoBack : false
            canGoForward: webContainer.currentActiveView ? webContainer.currentActiveView.canGoForward : false
            threshold: 90.0
            onBackTriggered: {
                if (webContainer.currentActiveView && webContainer.currentActiveView.canGoBack)
                    webContainer.currentActiveView.goBack()
            }
            onForwardTriggered: {
                if (webContainer.currentActiveView && webContainer.currentActiveView.canGoForward)
                    webContainer.currentActiveView.goForward()
            }
        }

        Repeater {
            id: workspaceRepeater
            model: workspaceModel
            Item {
                id: workspaceContainer
                width: parent.width
                height: parent.height
                readonly property int wsIndex: index
                readonly property var wsTabModel: workspaceModel.tabModel(model.id)
                readonly property real diff: wsIndex - webContainer.animatedWorkspaceIndex
                visible: Math.abs(diff) < 1.05
                enabled: Math.abs(diff) < 0.1
                z: (workspaceModel.currentIndex === wsIndex) ? 10 : 1

                transform: [
                    Translate { x: Math.round(workspaceContainer.diff * workspaceContainer.width) },
                    Scale {
                        origin.x: workspaceContainer.width / 2
                        origin.y: workspaceContainer.height / 2
                        xScale: 1.0 - (Math.min(1.0, Math.abs(workspaceContainer.diff)) * 0.08)
                        yScale: 1.0 - (Math.min(1.0, Math.abs(workspaceContainer.diff)) * 0.08)
                    }
                ]
                opacity: Math.max(0.0, 1.0 - (Math.abs(diff) * 1.25))

                property alias tabModel: workspaceContainer.wsTabModel
                property alias viewRepeater: tabViewRepeater

                Repeater {
                    id: tabViewRepeater
                    model: workspaceContainer.wsTabModel

                    Item {
                        id: pageContainer
                        anchors.fill: parent

                        readonly property bool isCurrentPage:
                            (workspaceModel.currentIndex === wsIndex)
                            && (workspaceContainer.wsTabModel
                                && workspaceContainer.wsTabModel.currentIndex === index)

                        visible: isCurrentPage

                        property alias engine: webEngineLoader.item

                        readonly property string urlStr:
                            model.url ? model.url.toString() : ""

                        readonly property bool isBlank:
                            urlStr === "about:blank" || urlStr === ""

                        readonly property bool isHistory:
                            urlStr === "ciel://history" ||
                            urlStr === "about:history"

                        readonly property bool isProfilePage:
                            urlStr === "ciel://profiles"

                        onIsCurrentPageChanged: {
                            if (isCurrentPage) {
                                if (webEngineLoader.item) {
                                    webContainer.currentActiveView = webEngineLoader.item
                                } else if (!webEngineLoader.active) {
                                    webEngineLoader.active = true
                                }
                            }
                        }

                        property bool engineStarted: false

                        Connections {
                            target: window

                            function onAfterRendering() {
                                if (pageContainer.engineStarted)
                                    return

                                pageContainer.engineStarted = true
                                webEngineLoader.active = true
                            }
                        }

                        Loader {
                            id: webEngineLoader

                            anchors.fill: parent
                            active: false
                            asynchronous: true
                            sourceComponent: webEngineComponent

                            onLoaded: {
                                if (!item)
                                    return

                                if (!pageContainer.isProfilePage &&
                                    !pageContainer.isHistory) {
                                    item.url = pageContainer.urlStr
                                }

                                if (pageContainer.isCurrentPage) {
                                    webContainer.currentActiveView = item
                                }
                            }
                        }
                        // Item {
                        //     anchors.centerIn: parent
                        //     width: 100
                        //     height: 100
                        //
                        //     CielLoadingSpinner {
                        //         anchors.centerIn: parent
                        //         implicitWidth: 16
                        //         implicitHeight: 16
                        //         orbitRadius: 4.5
                        //         minDotSize: 1.2
                        //         maxDotSize: 3.2
                        //         finalSize: 2.8
                        //         finished: false // pageContainer.engineStarted
                        //         color: Theme.accent
                        //         opacity: 1 // !finished
                        //         visible: opacity > 0.0
                        //
                        //         Behavior on opacity {
                        //           NumberAnimation {
                        //             duration: 1000
                        //           }
                        //         }
                        //     }
                        //   }

                        Component {
                            id: webEngineComponent

                            WebEngineView {
                                id: engineView

                                anchors.fill: parent

                                backgroundColor: Theme.background

                                visible:
                                    !pageContainer.isBlank &&
                                    !pageContainer.isHistory &&
                                    !pageContainer.isProfilePage

                                profile: window.currentWebProfile

                                onFeaturePermissionRequested: (securityOrigin, feature) => {
                                    let name = "Unknown Feature";
                                    let icon = "info";

                                    switch(feature) {
                                        case WebEngineView.MediaAudioCapture: name = "Microphone"; icon = "microphone"; break;
                                        case WebEngineView.MediaVideoCapture: name = "Camera"; icon = "camera"; break;
                                        case WebEngineView.MediaAudioVideoCapture: name = "Camera and Microphone"; icon = "camera"; break;
                                        case WebEngineView.DesktopVideoCapture:
                                        case WebEngineView.DesktopAudioVideoCapture: name = "Screen Sharing"; icon = "monitor"; break;
                                        case WebEngineView.Geolocation: name = "Location"; icon = "map-pin"; break;
                                        case WebEngineView.Notifications: name = "Notifications"; icon = "bell"; break;
                                        default:
                                            engineView.grantFeaturePermission(securityOrigin, feature, false);
                                            return; 
                                    }

                                    // PASS engineView directly!
                                    permissionDropdown.show(engineView, securityOrigin, feature, name, icon);
                                }


    onTooltipRequested: (request) => {
        request.accepted = true; // Prevent native tooltip

        if (request.text === "" || request.type === TooltipRequest.Hide) {
            customToolTip.close();
        } else {
            customToolTip.text = request.text;
            
            // Map engine's local coordinates to the tooltip's parent (Window.contentItem)
            var mappedPos = engineView.mapToItem(customToolTip.parent, request.x, request.y);
            customToolTip.openAt(mappedPos.x, mappedPos.y);
        }
    }

    // Instantiate the tooltip (it will auto-attach to the window overlay)
    CielToolTip {
        id: customToolTip
    }


                                onContextMenuRequested: (request) => {
                                    request.accepted = true; // Prevent the default engine context menu
                                    
                                    webContextMenu.contextRequest = request;
                                    
                                    // 1. Safely extract coordinates (Qt 6 uses request.position, Qt 5 used request.x/y)
                                    const rawX = request.position ? request.position.x : (request.x !== undefined ? request.x : 0);
                                    const rawY = request.position ? request.position.y : (request.y !== undefined ? request.y : 0);
                                    
                                    // 2. Map the coordinates from the WebEngineView's local space 
                                    // to the CielDropDown's parent coordinate space.
                                    // This automatically adds the tab bar offset, no matter where CielDropDown is placed!
                                    const targetParent = webContextMenu.parent || window.contentItem;
                                    const mappedPos = engineView.mapToItem(targetParent, rawX, rawY);
                                    
                                    webContextMenu.popup(rawX, rawY, this);
                                }

                                onJavaScriptDialogRequested: (request) => {
                                    request.accepted = true; // Prevent the default JS dialog
                                    
                                    jsDialogPopup.dialogRequest = request;
                                    jsDialogPopup.dialogMessage = request.message;
                                    jsDialogPopup.dialogTitle = request.title || "Message";
                                    jsDialogPopup.dialogType = request.type;
                                    jsDialogPopup.dialogDefaultText = request.defaultText;
                                    jsDialogPopup.open();
                                }

                                onNewWindowRequested: (request) => {
                                    if (request.destination ===
                                            WebEngineNewWindowRequest.InNewTab ||
                                        request.destination ===
                                            WebEngineNewWindowRequest.InNewBackgroundTab) {

                                        if (workspaceContainer.wsTabModel) {
                                            workspaceContainer.wsTabModel.addTab(
                                                request.requestedUrl
                                            )
                                            request.accepted = true
                                        }
                                    } else {
                                        var spawnedWindow =
                                            browserWindowComponent.createObject(window)

                                        if (spawnedWindow) {
                                            spawnedWindow.view.acceptAsNewWindow(request)
                                        }
                                    }
                                }

                                onTitleChanged: {
                                    if (workspaceContainer.wsTabModel &&
                                        !pageContainer.isHistory) {
                                        workspaceContainer.wsTabModel.updateTitle(
                                            index,
                                            title
                                        )
                                    }
                                }

                                onUrlChanged: {
                                    if (workspaceContainer.wsTabModel) {
                                        workspaceContainer.wsTabModel.updateUrl(
                                            index,
                                            url
                                        )
                                    }
                                }

                                onLoadingChanged: loadRequest => {
                                    if (workspaceContainer.wsTabModel) {
                                        workspaceContainer.wsTabModel.updateLoading(
                                            index,
                                            loading
                                        )
                                        workspaceContainer.wsTabModel.updateNavigation(
                                            index,
                                            canGoBack,
                                            canGoForward
                                        )
                                    }
                                }

                                onLoadProgressChanged: {
                                    if (workspaceContainer.wsTabModel) {
                                        workspaceContainer.wsTabModel.updateProgress(
                                            index,
                                            loadProgress
                                        )
                                    }
                                }
                            }
                        }

                        StartPage {
                            anchors.fill: parent
                            visible: pageContainer.isBlank
                            config: browserConfig
                            activeView: webEngineLoader.item
                        }

                        ProfilePage {
                            anchors.fill: parent
                            visible: pageContainer.isProfilePage
                            config: browserConfig
                            activeView: webEngineLoader.item
                        }

                        HistoryPage {
                            anchors.fill: parent
                            visible: pageContainer.isHistory

                            onOpenTabRequested: targetUrl => {
                                if (workspaceContainer.wsTabModel)
                                    workspaceContainer.wsTabModel.addTab(targetUrl)
                            }
                        }

                        Item {
                            id: permissionDropdown
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: visible ? menuCard.implicitHeight : 0
                            visible: isOpen || openProgress > 0.0
                            z: 100

                            property bool isOpen: false
                            
                            property var targetView: null 
                            property url currentSecurityOrigin: ""
                            property int currentFeature: -1
                            property string permissionName: ""
                            property string permissionIcon: "info"

                            property real openProgress: isOpen ? 1.0 : 0.0
                            Behavior on openProgress {
                                CielSpring { 
                                    damping: 0.32
                                    spring: 5.2
                                    mass: 1.0
                                    epsilon: 0.001
                                }
                            }

                            function show(view, origin, feature, name, icon) {
                                targetView = view;
                                currentSecurityOrigin = origin;
                                currentFeature = feature;
                                permissionName = name;
                                permissionIcon = icon;
                                isOpen = true;
                            }

                            function hide() {
                                isOpen = false;
                                targetView = null;
                                currentSecurityOrigin = "";
                                currentFeature = 0;
                            }

                            Item {
                                id: menuCard
                                anchors.top: parent.top
                                // anchors.left: parent.left
                                // anchors.right: parent.right
                                anchors.topMargin: 16
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(parent.width - 32, 800)
                                
                                height: menuColumn.implicitHeight + 32
                                
                                scale: 0.94 + (permissionDropdown.openProgress * 0.06)
                                opacity: Math.min(1.0, permissionDropdown.openProgress * 1.8)

                                CielSquircle {
                                    anchors.fill: parent
                                    color: Theme.surface
                                    borderWidth: 1
                                    borderColor: Theme.border
                                }

                                RowLayout {
                                    id: menuColumn
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    CielIcon {
                                        icon: permissionDropdown.permissionIcon
                                        size: Theme.MEDIUM
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Text {
                                        text: `Allow this site to use your ${permissionDropdown.permissionName}?`
                                        font.pixelSize: 15
                                        font.weight: Font.Medium
                                        color: Theme.textPrimary
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        wrapMode: Text.Wrap
                                    }

                                    CielButton {
                                        text: "Block"
                                        primary: false
                                        Layout.alignment: Qt.AlignVCenter
                                        onClicked: {
                                            if (permissionDropdown.targetView && permissionDropdown.currentFeature !== -1) {
                                              permissionDropdown.targetView.grantFeaturePermission(
                                                    permissionDropdown.currentSecurityOrigin, 
                                                    permissionDropdown.currentFeature, 
                                                    false
                                                );
                                            }
                                            permissionDropdown.hide();
                                        }
                                    }

                                    CielButton {
                                        text: "Allow"
                                        primary: true
                                        Layout.alignment: Qt.AlignVCenter
                                        
                                        onClicked: {
                                            if (permissionDropdown.targetView && permissionDropdown.currentFeature !== -1) {
                                              permissionDropdown.targetView.grantFeaturePermission(
                                                    permissionDropdown.currentSecurityOrigin, 
                                                    permissionDropdown.currentFeature, 
                                                    true
                                                );
                                            }
                                            permissionDropdown.hide();
                                        }
                                    }
                                    
                                    CielIconButton {
                                        icon: "x"
                                        size: Theme.MEDIUM
                                        Layout.alignment: Qt.AlignVCenter
                                        
                                        onClicked: {
                                            permissionDropdown.hide();
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: permissionDropdown.isOpen
                                onClicked: permissionDropdown.hide()
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: backIndicator
            anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 44; z: 99
            readonly property real prog: webContainer.animatedBackProgress
            readonly property bool triggered: prog >= 1.0
            property real currentRadius: triggered ? 22 : 12
            Behavior on currentRadius {
                CielSpring { damping: 0.28; spring: 5.4; mass: 0.9; epsilon: 0.001 }
            }
            visible: prog > 0.001
            opacity: Math.min(1.0, prog * 3.5)
            scale: triggered ? 1.06 : (0.84 + (0.16 * Math.min(1.0, prog)))
            x: -width + (prog * (width + 24))
            Behavior on scale {
                CielSpring { damping: 0.28; spring: 5.4; mass: 0.9; epsilon: 0.001 }
            }
            CielSquircle {
                id: backCardBg
                anchors.fill: parent
                radius: backIndicator.currentRadius
                color: backIndicator.triggered ? Theme.accent : Theme.surface
                borderWidth: backIndicator.triggered ? 0 : 1
                borderColor: Theme.border
                visible: false
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            MultiEffect {
                anchors.fill: backCardBg
                source: backCardBg
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.12)
                shadowBlur: 0.7
                shadowVerticalOffset: 3
                shadowHorizontalOffset: 0
            }
            CielIcon {
                anchors.centerIn: parent
                icon: "arrow-left"
                size: Theme.MEDIUM
                color: backIndicator.triggered ? "#FFFFFF" : Theme.textPrimary
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }

        Item {
            id: forwardIndicator
            anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 44; z: 99
            readonly property real prog: webContainer.animatedForwardProgress
            readonly property bool triggered: prog >= 1.0
            property real currentRadius: triggered ? 22 : 12
            Behavior on currentRadius {
                CielSpring { damping: 0.28; spring: 5.4; mass: 0.9; epsilon: 0.001 }
            }
            visible: prog > 0.001
            opacity: Math.min(1.0, prog * 3.5)
            scale: triggered ? 1.06 : (0.84 + (0.16 * Math.min(1.0, prog)))
            x: parent.width - (prog * (width + 24))
            Behavior on scale {
                CielSpring { damping: 0.28; spring: 5.4; mass: 0.9; epsilon: 0.001 }
            }
            CielSquircle {
                id: forwardCardBg
                anchors.fill: parent
                radius: forwardIndicator.currentRadius
                color: forwardIndicator.triggered ? Theme.accent : Theme.surface
                borderWidth: forwardIndicator.triggered ? 0 : 1
                borderColor: Theme.border
                visible: false
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            MultiEffect {
                anchors.fill: forwardCardBg
                source: forwardCardBg
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.12)
                shadowBlur: 0.7
                shadowVerticalOffset: 3
                shadowHorizontalOffset: 0
            }
            CielIcon {
                anchors.centerIn: parent
                icon: "arrow-right"
                size: Theme.MEDIUM
                color: forwardIndicator.triggered ? "#FFFFFF" : Theme.textPrimary
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
    }

    // TODO: Impl real new window
    Component {
        id: browserWindowComponent

        Window {
            id: newWindow
            width: 1024
            height: 768
            visible: true
            
            onClosing: newWindow.destroy() 

            property alias view: newEngineView

            WebEngineView {
                id: newEngineView
                anchors.fill: parent
                profile: window.currentWebProfile
                backgroundColor: Theme.background
            }
        }
    }


    CielContextMenu {
        id: webContextMenu
        // useAbsoluteCoordinates: true
        
        property var contextRequest: null

        // --- Custom App-Specific Actions ---
        // CielMenuItem {
        //     text: "New tab to the bottom"
        //     icon: "tab-new"
        //     onTriggered: {
        //         if (workspaceContainer.wsTabModel) {
        //             workspaceContainer.wsTabModel.addTab("about:blank");
        //         }
        //         webContextMenu.close();
        //     }
        // }
        //
        // CielMenuItem {
        //     text: "Move tab to new window"
        //     icon: "window-new"
        //     onTriggered: {
        //         webContextMenu.close();
        //         // Wire this to your actual window-management logic if implemented
        //         console.log("Move tab to new window requested for index:", index);
        //     }
        // }
        //
        // CielMenuSeparator {}

        // --- Dynamic WebEngine Actions ---

        // 1. Navigation Actions
        CielMenuItem {
            text: "Back"
                    icon: "arrow-left"
            visible: webContainer.currentActiveView ? webContainer.currentActiveView.canGoBack : false
            onTriggered: { if (webContainer.currentActiveView) { webContainer.currentActiveView.goBack(); } webContextMenu.close(); }
        }
        CielMenuItem {
            text: "Forward"
                    icon: "arrow-right"
            visible: webContainer.currentActiveView ? webContainer.currentActiveView.canGoForward : false
            onTriggered: { if (webContainer.currentActiveView) { webContainer.currentActiveView.goForward(); } webContextMenu.close(); }
        }
        CielMenuItem {
            text: "Reload"
            icon: "arrow-clockwise"
            onTriggered: { if (webContainer.currentActiveView) { webContainer.currentActiveView.reload(); } webContextMenu.close(); }
        }

        CielMenuSeparator { 
          visible: (webContextMenu.contextRequest?.selectedText !== "") // || (webContextMenu.contextRequest?.editFlags?.canCopy) 
        }

        // 4. Text Selection & Edit Actions
        CielMenuItem {
            text: {
                const txt = webContextMenu.contextRequest?.selectedText || "";
                return "Search Google for \"" + txt.substring(0, 8) + (txt.length > 8 ? "..." : "") + "\"";
            }
                            icon: "magnifying-glass"
            visible: webContextMenu.contextRequest?.selectedText !== ""
            onTriggered: {
                if (workspaceContainer.wsTabModel && webContextMenu.contextRequest?.selectedText) {
                    const query = encodeURIComponent(webContextMenu.contextRequest.selectedText);
                    workspaceContainer.wsTabModel.addTab("https://www.google.com/search?q=" + query);
                }
                webContextMenu.close();
            }
        }

        CielMenuSeparator { 
            visible: (webContextMenu.contextRequest?.linkUrl !== "") || (webContextMenu.contextRequest?.selectedText !== "") 
        }

        // 2. Link Actions
        CielMenuItem {
            text: "Open link in new tab"
            icon: ""
            visible: webContextMenu.contextRequest?.linkUrl !== ""
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.triggerWebAction(WebEngineView.OpenLinkInNewTab);
                }
                webContextMenu.close();
            }
        }
        CielMenuItem {
            text: "Copy link address"
            icon: ""
            visible: webContextMenu.contextRequest?.linkUrl !== ""
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.triggerWebAction(WebEngineView.CopyLinkToClipboard);
                }
                webContextMenu.close();
            }
        }

        CielMenuSeparator { visible: webContextMenu.contextRequest?.mediaType === 2 } // MediaTypeImage

        // 3. Image Actions
        CielMenuItem {
            text: "Copy image"
            visible: webContextMenu.contextRequest?.mediaType === 2
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.triggerWebAction(WebEngineView.CopyImageToClipboard);
                }
                webContextMenu.close();
            }
        }
        CielMenuItem {
            text: "Copy image address"
            visible: webContextMenu.contextRequest?.mediaType === 2
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.triggerWebAction(WebEngineView.CopyImageUrlToClipboard);
                }
                webContextMenu.close();
            }
        }

        CielMenuItem {
            text: "Copy"
            visible: webContextMenu.contextRequest?.editFlags?.canCopy ?? false
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.triggerWebAction(WebEngineView.Copy);
                }
                webContextMenu.close();
            }
        }
        CielMenuItem {
            text: "Paste"
            visible: webContextMenu.contextRequest?.editFlags?.canPaste ?? false
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.triggerWebAction(WebEngineView.Paste);
                }
                webContextMenu.close();
            }
        }
        CielMenuItem {
            text: "Select All"
            visible: webContextMenu.contextRequest?.editFlags?.canSelectAll ?? false
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.triggerWebAction(WebEngineView.SelectAll);
                }
                webContextMenu.close();
            }
        }

        CielMenuSeparator {
            visible: webContextMenu.contextRequest?.selectedText !== ""
        }

        // 5. Page Actions
        CielMenuItem {
            text: "View page source"
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.triggerWebAction(WebEngineView.ViewSource);
                }
                webContextMenu.close();
            }
        }
        // CielMenuItem {
        //     text: "Inspect"
        //     onTriggered: {
        //         if (webContainer.currentActiveView) {
        //             webContainer.currentActiveView.triggerWebAction(WebEngineView.InspectElement);
        //         }
        //         webContextMenu.close();
        //     }
        // }
    }

    CielPopup {
        id: jsDialogPopup
        
        // Dynamic width
        contentWidth: 380
        
        // Dynamic height: implicit height of the column + top/bottom margins (20 + 20 = 40)
        contentHeight: dialogColumn.implicitHeight + 40

        property var dialogRequest: null
        property string dialogMessage: ""
        property string dialogTitle: "Message"
        property int dialogType: 0 // 0: Alert, 1: Confirm, 2: Prompt, 3: BeforeUnload
        property string dialogDefaultText: ""
        
        property bool _requestResolved: false

        // Prevent website hangs on outside click / Esc
        onClosed: {
            if (dialogRequest && !_requestResolved) {
                dialogRequest.dialogReject();
            }
            dialogRequest = null;
            _requestResolved = false;
            promptInput.text = "";
        }

        ColumnLayout {
            id: dialogColumn
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12 // Adjust to 2 here if you want extremely tight spacing

            Text {
                text: jsDialogPopup.dialogTitle
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: Theme.textPrimary
            }

            Text {
                text: jsDialogPopup.dialogMessage
                font.pixelSize: 13
                color: Theme.textPrimary
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                // Cap the maximum height so extremely long messages don't break the screen, 
                // but otherwise it grows dynamically to fit the text.
                Layout.maximumHeight: 200 
            }

            CielSearch {
                id: promptInput
                visible: jsDialogPopup.dialogType === 2
                text: jsDialogPopup.dialogDefaultText
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                placeholder: "Enter text..."

                preContent: Item {}
                postContent: Item {}
                
                onVisibleChanged: {
                    if (visible) {
                        Qt.callLater(function() {
                            if (promptInput.inputField) {
                                promptInput.inputField.forceActiveFocus();
                                promptInput.inputField.selectAll();
                            }
                        });
                    }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        event.accepted = true;
                        okButton.onClicked();
                    }
                }
            }

            // This item contributes 0 to implicitHeight, but pushes buttons to the bottom 
            // IF the popup is ever forced to be taller than its content.
            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Layout.alignment: Qt.AlignRight

                CielButton {
                    id: cancelButton
                    text: "Cancel"
                    visible: jsDialogPopup.dialogType !== 0
                    primary: false
                    
                    onClicked: {
                        if (jsDialogPopup.dialogRequest) {
                            jsDialogPopup._requestResolved = true;
                            jsDialogPopup.dialogRequest.dialogReject();
                        }
                        jsDialogPopup.close();
                    }
                }

                CielButton {
                    id: okButton
                    text: "OK"
                    primary: true
                    
                    onClicked: {
                        if (jsDialogPopup.dialogRequest) {
                            jsDialogPopup._requestResolved = true;
                            if (jsDialogPopup.dialogType === 2) {
                                jsDialogPopup.dialogRequest.dialogAccept(promptInput.text);
                            } else {
                                jsDialogPopup.dialogRequest.dialogAccept();
                            }
                        }
                        jsDialogPopup.close();
                    }
                }
            }
        }
    }
}
