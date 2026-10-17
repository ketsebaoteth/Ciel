import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine
import QtQuick.Dialogs
import QtWebChannel
import QtCore
import QtQuick.Effects
import Ciel.Ui
import Ciel.Browser 1.0

import "../tabs"
import "../startpage"
import "../history"
import "../bookmark"

ApplicationWindow {
    id: window
    width: 1040
    height: 680
    minimumWidth: 640
    minimumHeight: 460
    visible: true

    property var windowManager: null
    property bool isPrivate: false
    property bool isPrimary: false
    property string initialUrl: ""
    property bool allowClose: false
    property bool profileReady: false
    property alias appSettings: browserSettings

    function openNewTab(url) {
        var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
        if (!model)
            return;
        if (!url) {
            var home = (browserSettings.homepage || "").trim();
            if (home === "")
                model.addTab();
            else
                model.addTab(browserSettings.resolveInput(home, function (text) {
                    return browserConfig.resolveQueryOrUrl(text);
                }));
        } else {
            model.addTab(browserConfig.resolveQueryOrUrl(url));
        }
    }

    function openSettings() {
        var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
        if (model)
            model.addTab("ciel://settings");
    }

    function applyProfileSettings() {
        var p = currentWebProfile;
        if (!p)
            return;
        if (!browserSettings.stockUserAgent && p.httpUserAgent)
            browserSettings.stockUserAgent = p.httpUserAgent;
        var ua = browserSettings.uaFor(browserSettings.userAgentPreset);
        if (ua)
            p.httpUserAgent = ua;
        p.spellCheckEnabled = browserSettings.spellCheckEnabled;
    }

    title: isPrivate ? "Browser — Private" : "Browser"

    color: Theme.background
    property int railOrientation: Qt.Vertical

    readonly property var currentWebProfile: !windowManager ? null : (isPrivate ? windowManager.privateProfile() : windowManager.profileFor(ProfileManager.activeProfileId))

    function startDownload(downloadUrl, fileName, mimeType) {
        browserConfig.startDownload(downloadUrl, fileName, mimeType);
        tabRail.downloadsPopup.open();
    }

    readonly property var pageScripts: {
        var list = [
            {
                name: "ciel-passwords",
                sourceCode: PasswordManager.injectedScript(),
                injectionPoint: WebEngineScript.DocumentReady,
                worldId: WebEngineScript.ApplicationWorld,
                runsOnSubFrames: false
            }
        ];

        if (isPrivate)
            return list;

        var ext = ExtensionManager.scripts;
        var points = {
            start: WebEngineScript.DocumentCreation,
            end: WebEngineScript.DocumentReady,
            idle: WebEngineScript.Deferred
        };
        for (var i = 0; i < ext.length; ++i) {
            list.push({
                name: ext[i].name,
                sourceCode: ext[i].sourceCode,
                injectionPoint: points[ext[i].runAt] ?? WebEngineScript.Deferred,
                worldId: ext[i].world === "main" ? WebEngineScript.MainWorld : WebEngineScript.UserWorld,
                runsOnSubFrames: ext[i].allFrames
            });
        }
        return list;
    }

    function openFind() {
        var v = webContainer.currentActiveView;
        if (!v || !v.visible)
            return;
        locationPopup.dismiss();
        findBar.open(v);
    }

    function openLocation(mode) {
        if (!mode) {
            var v = webContainer.currentActiveView;
            if (!v)
                return;
            if (findBar.isOpen)
                findBar.close();
            locationPopup.open(v);
        } else {
            locationPopup.newTab = true;
            locationPopup.open();
        }
    }

    function restoreClosedTab() {
        var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
        if (model)
            model.restoreClosedTab();
    }
    function permissionInfo(feature) {
        switch (feature) {
        case WebEngineView.MediaAudioCapture:
            return {
                keys: ["microphone"],
                name: "Microphone",
                icon: "microphone",
                persist: true
            };
        case WebEngineView.MediaVideoCapture:
            return {
                keys: ["camera"],
                name: "Camera",
                icon: "camera",
                persist: true
            };
        case WebEngineView.MediaAudioVideoCapture:
            return {
                keys: ["microphone", "camera"],
                name: "Camera and Microphone",
                icon: "camera",
                persist: true
            };
        case WebEngineView.DesktopVideoCapture:
        case WebEngineView.DesktopAudioVideoCapture:
            return {
                keys: [],
                name: "Screen Sharing",
                icon: "monitor",
                persist: false
            };
        case WebEngineView.Geolocation:
            return {
                keys: ["location"],
                name: "Location",
                icon: "map-pin",
                persist: true
            };
        case WebEngineView.Notifications:
            return {
                keys: ["notifications"],
                name: "Notifications",
                icon: "bell",
                persist: true
            };
        }
        return null;
    }

    property var sessionDecisions: ({})

    function storedDecision(origin, keys) {
        if (origin === "" || keys.length === 0)
            return "";
        var allGranted = true;
        for (var i = 0; i < keys.length; ++i) {
            var s = isPrivate ? (sessionDecisions[origin + "|" + keys[i]] || "") : SitePermissionManager.permissionState(origin, keys[i]);
            if (s === "denied")
                return "denied";
            if (s !== "granted")
                allGranted = false;
        }
        return allGranted ? "granted" : "";
    }

    function rememberDecision(origin, keys, granted) {
        var s = granted ? "granted" : "denied";
        for (var i = 0; i < keys.length; ++i) {
            if (isPrivate)
                sessionDecisions[origin + "|" + keys[i]] = s;
            else
                SitePermissionManager.setPermission(origin, keys[i], s);
        }
    }

    function localPathFromUrl(u) {
        var s = u.toString();
        s = s.replace(/^file:\/\/\/([A-Za-z]:)/, "$1");
        s = s.replace(/^file:\/\//, "");
        return decodeURIComponent(s);
    }

    function printCurrentPage() {
        var v = webContainer.currentActiveView;
        if (!v || !v.visible)
            return;
        var name = (v.title || "page").replace(/[\\\/:*?"<>|]+/g, "_").trim();
        if (name === "")
            name = "page";

        printDialog.printView = v;

        printDialog.currentFile = StandardPaths.writableLocation(StandardPaths.DocumentsLocation) + "/" + name + ".pdf";
        printDialog.open();
    }

    function savePageCurrent() {
        var v = webContainer.currentActiveView;
        if (!v || !v.visible)
            return;
        var name = (v.title || "page").replace(/[\\\/:*?"<>|]+/g, "_").trim();
        if (name === "")
            name = "page";

        saveDialog.saveView = v;
        saveDialog.currentFile = StandardPaths.writableLocation(StandardPaths.DocumentsLocation) + "/" + name + ".html";
        saveDialog.open();
    }

    readonly property var translateLanguages: [
        {
            name: "English",
            code: "en"
        },
        {
            name: "Spanish",
            code: "es"
        },
        {
            name: "French",
            code: "fr"
        },
        {
            name: "German",
            code: "de"
        },
        {
            name: "Italian",
            code: "it"
        },
        {
            name: "Portuguese",
            code: "pt"
        },
        {
            name: "Russian",
            code: "ru"
        },
        {
            name: "Arabic",
            code: "ar"
        },
        {
            name: "Chinese (Simplified)",
            code: "zh-CN"
        },
        {
            name: "Japanese",
            code: "ja"
        },
        {
            name: "Korean",
            code: "ko"
        },
        {
            name: "Hindi",
            code: "hi"
        },
        {
            name: "Turkish",
            code: "tr"
        }
    ]

    function translateUrl(urlStr, lang) {
        var m = urlStr.match(/^https?:\/\/([^\/?#:]+)(\/[^?#]*)?(\?[^#]*)?(#.*)?$/);
        if (!m) {
            return "https://translate.google.com/translate?sl=auto&tl=" + lang + "&u=" + encodeURIComponent(urlStr);
        }
        var host = m[1].replace(/-/g, "--").replace(/\./g, "-");
        var path = m[2] || "/";
        var query = m[3] ? m[3] + "&" : "?";
        return "https://" + host + ".translate.goog" + path + query + "_x_tr_sl=auto&_x_tr_tl=" + lang + "&_x_tr_hl=" + lang + "&_x_tr_pto=wapp" + (m[4] || "");
    }

    function originalUrl(urlStr) {
        var m = urlStr.match(/^https?:\/\/([^\/?#]+)\.translate\.goog(\/[^?#]*)?(\?[^#]*)?(#.*)?$/);
        if (!m)
            return urlStr;
        var host = m[1].replace(/--/g, "\u0000").replace(/-/g, ".").replace(/\u0000/g, "-");
        var params = m[3] ? m[3].slice(1).split("&").filter(function (p) {
            return p !== "" && p.indexOf("_x_tr_") !== 0;
        }) : [];
        return "https://" + host + (m[2] || "/") + (params.length ? "?" + params.join("&") : "") + (m[4] || "");
    }

    function openTranslate() {
        var v = webContainer.currentActiveView;
        if (!v || !v.visible)
            return;
        var u = v.url.toString();
        if (!/^https?:/.test(u))
            return;
        var sys = Qt.locale().name.split("_")[0];
        var idx = 0;
        for (var i = 0; i < translateLanguages.length; ++i) {
            if (translateLanguages[i].code.split("-")[0] === sys) {
                idx = i;
                break;
            }
        }
        translateSelect.currentIndex = idx;
        translatePopup.targetView = v;
        translatePopup.targetUrl = originalUrl(u);
        translatePopup.open();
    }

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

    BrowserSettings {
        id: browserSettings
    }

    WorkspaceModel {
        id: workspaceModel
        ephemeral: !window.isPrimary
        incognito: window.isPrivate
        startUrl: window.initialUrl
    }

    function openHistoryTab() {
        var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
        if (model)
            model.addTab("ciel://history");
    }

    function openBookmarksTab() {
        var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
        if (model)
            model.addTab("ciel://bookmarks");
    }

    TabBar {
        id: tabRail
        workspaceModel: workspaceModel
        getWorkspaceViews: idx => webContainer.getWorkspaceViews(idx)
        config: browserConfig
        browserSettings: browserSettings
        activeView: webContainer.currentActiveView
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.right: window.railOrientation === Qt.Horizontal ? parent.right : undefined
        anchors.bottom: window.railOrientation === Qt.Vertical ? parent.bottom : undefined
        z: 10
        isPrivate: window.isPrivate
        onHistoryRequested: openHistoryTab()
        onProfilesRequested: {
            var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
            if (model)
                model.addTab("ciel://profiles");
        }
        onNewTabRequested: window.openLocation("new")
        onBookmarksRequested: openBookmarksTab()
        onPasswordsRequested: {
            var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
            if (model)
                model.addTab("ciel://passwords");
        }
        onRestoreTabRequested: window.restoreClosedTab()
        onPrintRequested: window.printCurrentPage()
        onSavePageRequested: window.savePageCurrent()
        onTranslateRequested: window.openTranslate()
        onFindInPageRequested: window.openFind()
        onSettingsRequested: window.openSettings()
        onNewWindowRequested: window.windowManager.openWindow({})
        onNewPrivateWindowRequested: window.windowManager.openWindow({
            privateMode: true
        })
        onExtensionsRequested: {
            var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
            if (model)
                model.addTab("ciel://extensions");
        }
        onSitePermissionsRequested: {
            var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
            if (model)
                model.addTab("ciel://permissions");
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
            var item = workspaceRepeater.itemAt(idx);
            return item ? item.viewRepeater : null;
        }

        property var currentActiveView: null
        readonly property var activeTabModel: workspaceModel.tabModel(workspaceModel.currentWorkspaceId)

        property real animatedBackProgress: navFilter.backProgress
        property real animatedForwardProgress: navFilter.forwardProgress

        Behavior on animatedBackProgress {
            enabled: !navFilter.active
            CielSpring {
                damping: 0.32
                spring: 5.2
                mass: 1.0
                epsilon: 0.001
            }
        }
        Behavior on animatedForwardProgress {
            enabled: !navFilter.active
            CielSpring {
                damping: 0.32
                spring: 5.2
                mass: 1.0
                epsilon: 0.001
            }
        }

        SwipeGestureFilter {
            id: navFilter
            anchors.fill: parent
            canGoBack: webContainer.currentActiveView ? webContainer.currentActiveView.canGoBack : false
            canGoForward: webContainer.currentActiveView ? webContainer.currentActiveView.canGoForward : false
            threshold: 90.0
            onBackTriggered: {
                if (webContainer.currentActiveView && webContainer.currentActiveView.canGoBack)
                    webContainer.currentActiveView.goBack();
            }
            onForwardTriggered: {
                if (webContainer.currentActiveView && webContainer.currentActiveView.canGoForward)
                    webContainer.currentActiveView.goForward();
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
                    Translate {
                        x: Math.round(workspaceContainer.diff * workspaceContainer.width)
                    },
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

                        readonly property bool isCurrentPage: (workspaceModel.currentIndex === wsIndex) && (workspaceContainer.wsTabModel && workspaceContainer.wsTabModel.currentIndex === index)

                        visible: isCurrentPage

                        property alias engine: webEngineLoader.item

                        readonly property string urlStr: model.url ? model.url.toString() : ""

                        readonly property bool isBlank: urlStr === "about:blank" || urlStr === ""

                        readonly property bool isHistory: urlStr === "ciel://history" || urlStr === "about:history"
                        readonly property bool isPasswordsPage: urlStr === "ciel://passwords"

                        readonly property bool isProfilePage: urlStr === "ciel://profiles"
                        readonly property bool isBookmarksPage: urlStr === "ciel://bookmarks"
                        readonly property bool isSettingsPage: urlStr === "ciel://settings"
                        readonly property bool isExtensionsPage: urlStr === "ciel://extensions"
                        readonly property bool isPermissionsPage: urlStr === "ciel://permissions"

                        readonly property bool isInternalPage: isHistory || isProfilePage || isBookmarksPage || isPasswordsPage || isExtensionsPage || isPermissionsPage

                        onUrlStrChanged: {
                            if (isSettingsPage && workspaceContainer.wsTabModel)
                                workspaceContainer.wsTabModel.updateTitle(index, "Settings");
                        }
                        onIsCurrentPageChanged: {
                            if (isCurrentPage) {
                                if (webEngineLoader.item) {
                                    webContainer.currentActiveView = webEngineLoader.item;
                                } else if (!webEngineLoader.active) {
                                    webEngineLoader.active = true;
                                }
                            }
                        }

                        property bool engineStarted: false

                        Connections {
                            target: window

                            function onAfterRendering() {
                                if (pageContainer.engineStarted)
                                    return;
                                pageContainer.engineStarted = true;
                                webEngineLoader.active = true;
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
                                    return;
                                if (!pageContainer.isInternalPage) {
                                    item.url = pageContainer.urlStr;
                                }

                                if (pageContainer.isCurrentPage) {
                                    webContainer.currentActiveView = item;
                                }
                            }
                        }

                        Component {
                            id: webEngineComponent

                            WebEngineView {
                                id: engineView

                                anchors.fill: parent

                                backgroundColor: Theme.background

                                layer.enabled: true
                                layer.live: true

                                visible: !pageContainer.isBlank && !pageContainer.isInternalPage

                                profile: window.currentWebProfile

                                settings.javascriptEnabled: browserSettings.javascriptEnabled
                                settings.autoLoadImages: browserSettings.autoLoadImages
                                settings.localStorageEnabled: browserSettings.localStorageEnabled
                                settings.javascriptCanOpenWindows: browserSettings.javascriptCanOpenWindows
                                settings.hyperlinkAuditingEnabled: browserSettings.hyperlinkAuditingEnabled
                                settings.pdfViewerEnabled: browserSettings.pdfViewerEnabled
                                settings.scrollAnimatorEnabled: browserSettings.smoothScrolling
                                settings.javascriptCanAccessClipboard: true
                                settings.javascriptCanPaste: false

                                Component.onCompleted: zoomFactor = browserSettings.zoomFactor
                                Connections {
                                    target: browserSettings
                                    function onZoomFactorChanged() {
                                        engineView.zoomFactor = browserSettings.zoomFactor;
                                    }
                                }

                                onFeaturePermissionRequested: (securityOrigin, feature) => {
                                    var info = window.permissionInfo(feature);
                                    if (!info) {
                                        engineView.grantFeaturePermission(securityOrigin, feature, false);
                                        return;
                                    }

                                    var origin = SitePermissionManager.originOf(securityOrigin);
                                    var saved = info.persist ? window.storedDecision(origin, info.keys) : "";
                                    if (saved !== "") {
                                        engineView.grantFeaturePermission(securityOrigin, feature, saved === "granted");
                                        return;
                                    }

                                    permissionDropdown.show(engineView, securityOrigin, feature, info.name, info.icon, origin, info.keys, info.persist);
                                }

                                onTooltipRequested: request => {
                                    request.accepted = true;

                                    if (request.text === "" || request.type === TooltipRequest.Hide) {
                                        customToolTip.close();
                                    } else {
                                        customToolTip.text = request.text;

                                        var mappedPos = engineView.mapToItem(customToolTip.parent, request.x, request.y);
                                        customToolTip.openAt(mappedPos.x, mappedPos.y);
                                    }
                                }

                                CielToolTip {
                                    id: customToolTip
                                }

                                onContextMenuRequested: request => {
                                    request.accepted = true;

                                    webContextMenu.contextRequest = request;

                                    const rawX = request.position ? request.position.x : (request.x !== undefined ? request.x : 0);
                                    const rawY = request.position ? request.position.y : (request.y !== undefined ? request.y : 0);

                                    const targetParent = webContextMenu.parent || window.contentItem;
                                    const mappedPos = engineView.mapToItem(targetParent, rawX, rawY);

                                    webContextMenu.popup(rawX, rawY, this);
                                }

                                onJavaScriptDialogRequested: request => {
                                    request.accepted = true;

                                    jsDialogPopup.dialogRequest = request;
                                    jsDialogPopup.dialogMessage = request.message;
                                    jsDialogPopup.dialogTitle = request.title || "Message";
                                    jsDialogPopup.dialogType = request.type;
                                    jsDialogPopup.dialogDefaultText = request.defaultText;
                                    jsDialogPopup.open();
                                }

                                onNewWindowRequested: request => {
                                    var d = request.destination;
                                    if (d === WebEngineNewWindowRequest.InNewTab || d === WebEngineNewWindowRequest.InNewBackgroundTab) {
                                        if (workspaceContainer.wsTabModel) {
                                            workspaceContainer.wsTabModel.addTab(request.requestedUrl);
                                            request.accepted = true;
                                        }
                                    } else if (d === WebEngineNewWindowRequest.InNewWindow) {
                                        window.windowManager.openWindow({
                                            url: request.requestedUrl,
                                            privateMode: window.isPrivate
                                        });
                                        request.accepted = true;
                                    } else {
                                        var spawnedWindow = browserWindowComponent.createObject(window);

                                        if (spawnedWindow) {
                                            spawnedWindow.view.acceptAsNewWindow(request);
                                        }
                                    }
                                }

                                onTitleChanged: {
                                    if (workspaceContainer.wsTabModel && !pageContainer.isInternalPage) {
                                        workspaceContainer.wsTabModel.updateTitle(index, title);
                                    }
                                }

                                onUrlChanged: {
                                    if (workspaceContainer.wsTabModel) {
                                        workspaceContainer.wsTabModel.updateUrl(index, url);
                                    }
                                }

                                onLoadingChanged: loadRequest => {
                                    if (workspaceContainer.wsTabModel) {
                                        workspaceContainer.wsTabModel.updateLoading(index, loading);
                                        workspaceContainer.wsTabModel.updateNavigation(index, canGoBack, canGoForward);
                                    }
                                }

                                onLoadProgressChanged: {
                                    if (workspaceContainer.wsTabModel) {
                                        workspaceContainer.wsTabModel.updateProgress(index, loadProgress);
                                    }
                                }

                                webChannel: WebChannel {
                                    registeredObjects: [passwordBridge]
                                }
                                webChannelWorld: WebEngineScript.ApplicationWorld

                                userScripts.collection: window.pageScripts

                                PasswordBridge {
                                    id: passwordBridge
                                    WebChannel.id: "cielPasswords"
                                    onSaveOffered: (host, username, isUpdate) => {
                                        if (!window.isPrivate)
                                            passwordBar.show(passwordBridge, host, username, isUpdate);
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
                                    workspaceContainer.wsTabModel.addTab(targetUrl);
                            }
                        }

                        BookmarkPage {
                            anchors.fill: parent
                            visible: pageContainer.isBookmarksPage

                            onOpenTabRequested: targetUrl => {
                                if (workspaceContainer.wsTabModel)
                                    workspaceContainer.wsTabModel.addTab(targetUrl);
                            }
                        }

                        PasswordPage {
                            anchors.fill: parent
                            visible: pageContainer.isPasswordsPage
                        }

                        ExtensionsPage {
                            anchors.fill: parent
                            visible: pageContainer.isExtensionsPage
                        }

                        SitePermissionsPage {
                            anchors.fill: parent
                            visible: pageContainer.isPermissionsPage
                        }

                        SettingsPage {
                            anchors.fill: parent
                            visible: pageContainer.isSettingsPage
                            settings: browserSettings
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

                            property string currentOrigin: ""
                            property string currentHost: ""
                            property var currentKeys: []
                            property bool currentPersist: false

                            function show(view, origin, feature, name, icon, normOrigin, keys, persist) {
                                targetView = view;
                                currentSecurityOrigin = origin;
                                currentFeature = feature;
                                permissionName = name;
                                permissionIcon = icon;
                                currentOrigin = normOrigin;
                                currentHost = normOrigin.replace(/^[a-z]+:\/\//, "");
                                currentKeys = keys;
                                currentPersist = persist;
                                isOpen = true;
                            }

                            function decide(granted) {
                                if (targetView && currentFeature !== -1) {
                                    targetView.grantFeaturePermission(currentSecurityOrigin, currentFeature, granted);
                                    if (currentPersist && currentOrigin !== "")
                                        window.rememberDecision(currentOrigin, currentKeys, granted);
                                }
                                hide();
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
                                        text: `Allow ${permissionDropdown.currentHost} to use your ${permissionDropdown.permissionName}?`
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
                                        onClicked: permissionDropdown.decide(false)
                                    }

                                    CielButton {
                                        text: "Allow"
                                        primary: true
                                        Layout.alignment: Qt.AlignVCenter
                                        onClicked: permissionDropdown.decide(true)
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

                        Item {
                            id: passwordBar
                            anchors.top: parent.top
                            anchors.topMargin: 16 + (permissionDropdown.isOpen ? 72 : 0)
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width - 32, 800)
                            height: barRow.implicitHeight + 32
                            z: 101
                            visible: openProgress > 0.0

                            property bool isOpen: false
                            property var targetBridge: null
                            property string host: ""
                            property string username: ""
                            property bool isUpdate: false

                            property real openProgress: isOpen ? 1.0 : 0.0
                            Behavior on openProgress {
                                CielSpring {
                                    damping: 0.32
                                    spring: 5.2
                                    mass: 1.0
                                    epsilon: 0.001
                                }
                            }
                            scale: 0.94 + (openProgress * 0.06)
                            opacity: Math.min(1.0, openProgress * 1.8)

                            function show(bridge, h, u, update) {
                                targetBridge = bridge;
                                host = h;
                                username = u;
                                isUpdate = update;
                                isOpen = true;
                            }

                            function finish(accept) {
                                if (targetBridge) {
                                    if (accept)
                                        targetBridge.acceptPending();
                                    else
                                        targetBridge.discardPending();
                                }
                                isOpen = false;
                                targetBridge = null;
                            }

                            CielSquircle {
                                anchors.fill: parent
                                color: Theme.surface
                                borderWidth: 1
                                borderColor: Theme.border
                            }

                            RowLayout {
                                id: barRow
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 12

                                CielIcon {
                                    icon: "key"
                                    size: Theme.MEDIUM
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: (passwordBar.isUpdate ? "Update" : "Save") + " password for " + (passwordBar.username !== "" ? passwordBar.username : "this account") + " on " + passwordBar.host + "?"
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                    color: Theme.textPrimary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                CielButton {
                                    text: "Not now"
                                    primary: false
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: passwordBar.finish(false)
                                }

                                CielButton {
                                    text: passwordBar.isUpdate ? "Update" : "Save"
                                    primary: true
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: passwordBar.finish(true)
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: backIndicator
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            z: 99
            readonly property real prog: webContainer.animatedBackProgress
            readonly property bool triggered: prog >= 1.0
            property real currentRadius: triggered ? 22 : 12
            Behavior on currentRadius {
                CielSpring {
                    damping: 0.28
                    spring: 5.4
                    mass: 0.9
                    epsilon: 0.001
                }
            }
            visible: prog > 0.001
            opacity: Math.min(1.0, prog * 3.5)
            scale: triggered ? 1.06 : (0.84 + (0.16 * Math.min(1.0, prog)))
            x: -width + (prog * (width + 24))
            Behavior on scale {
                CielSpring {
                    damping: 0.28
                    spring: 5.4
                    mass: 0.9
                    epsilon: 0.001
                }
            }
            CielSquircle {
                id: backCardBg
                anchors.fill: parent
                radius: backIndicator.currentRadius
                color: backIndicator.triggered ? Theme.accent : Theme.surface
                borderWidth: backIndicator.triggered ? 0 : 1
                borderColor: Theme.border
                visible: false
                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
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
                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
            }
        }

        Item {
            id: forwardIndicator
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            z: 99
            readonly property real prog: webContainer.animatedForwardProgress
            readonly property bool triggered: prog >= 1.0
            property real currentRadius: triggered ? 22 : 12
            Behavior on currentRadius {
                CielSpring {
                    damping: 0.28
                    spring: 5.4
                    mass: 0.9
                    epsilon: 0.001
                }
            }
            visible: prog > 0.001
            opacity: Math.min(1.0, prog * 3.5)
            scale: triggered ? 1.06 : (0.84 + (0.16 * Math.min(1.0, prog)))
            x: parent.width - (prog * (width + 24))
            Behavior on scale {
                CielSpring {
                    damping: 0.28
                    spring: 5.4
                    mass: 0.9
                    epsilon: 0.001
                }
            }
            CielSquircle {
                id: forwardCardBg
                anchors.fill: parent
                radius: forwardIndicator.currentRadius
                color: forwardIndicator.triggered ? Theme.accent : Theme.surface
                borderWidth: forwardIndicator.triggered ? 0 : 1
                borderColor: Theme.border
                visible: false
                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
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
                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
            }
        }
    }

    Item {
        id: findBar
        anchors.top: webContainer.top
        anchors.right: webContainer.right
        anchors.topMargin: 12
        anchors.rightMargin: 16
        width: 380
        height: 48
        z: 60
        visible: openProgress > 0.0

        property bool isOpen: false
        property var view: null
        property int matches: 0
        property int active: 0
        property bool searched: false

        property real openProgress: isOpen ? 1.0 : 0.0
        Behavior on openProgress {
            CielSpring {
                damping: 0.32
                spring: 5.2
                mass: 1.0
                epsilon: 0.001
            }
        }
        opacity: Math.min(1.0, openProgress * 1.8)
        scale: 0.94 + (openProgress * 0.06)

        function open(v) {
            if (view && view !== v)
                view.findText("");
            view = v;
            isOpen = true;
            Qt.callLater(function () {
                findInput.inputField.forceActiveFocus();
                findInput.inputField.selectAll();
            });
            if (findInput.text !== "")
                run(false);
        }

        function close() {
            if (view)
                view.findText("");
            isOpen = false;
            view = null;
            matches = 0;
            active = 0;
            searched = false;
        }

        function run(backward) {
            if (!view)
                return;
            if (findInput.text === "") {
                view.findText("");
                matches = 0;
                active = 0;
                searched = false;
                return;
            }
            view.findText(findInput.text, backward ? WebEngineView.FindBackward : 0);
        }

        Connections {
            target: findBar.view
            ignoreUnknownSignals: true
            function onFindTextFinished(result) {
                findBar.matches = result.numberOfMatches;
                findBar.active = result.activeMatchOrdinal ?? 0;
                findBar.searched = true;
            }
        }

        CielSquircle {
            anchors.fill: parent
            color: Theme.surface
            borderWidth: 1
            borderColor: Theme.border
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            CielInput {
                id: findInput
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                placeholder: "Find in page"
                showBorder: false
                onTextChanged: findBar.run(false)
                onAccepted: query => findBar.run(false)
            }

            Text {
                text: (findBar.searched && findInput.text !== "") ? (findBar.matches > 0 ? findBar.active + "/" + findBar.matches : "No results") : ""
                font.pixelSize: 12
                color: Theme.textSecondary
                Layout.alignment: Qt.AlignVCenter
            }

            CielIconButton {
                icon: "arrow-up"
                size: Theme.XSMALL
                onClicked: findBar.run(true)
            }
            CielIconButton {
                icon: "arrow-down"
                size: Theme.XSMALL
                onClicked: findBar.run(false)
            }
            CielIconButton {
                icon: "x"
                size: Theme.XSMALL
                onClicked: findBar.close()
            }
        }
    }

    Item {
        id: locationPopup
        anchors.fill: parent
        z: 900
        visible: openProgress > 0.0

        property bool isOpen: false
        property string originUrl: ""
        property bool suppressQuery: false
        property real openProgress: isOpen ? 1.0 : 0.0
        property bool newTab: false

        Behavior on openProgress {
            CielSpring {
                damping: 0.32
                spring: 5.2
                mass: 1.0
                epsilon: 0.001
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -2

            onPressed: mouse => mouse.accepted = true
            onClicked: mouse => mouse.accepted = true
            onDoubleClicked: mouse => mouse.accepted = true

            onWheel: wheel => wheel.accepted = true

            hoverEnabled: true
            onPositionChanged: mouse => mouse.accepted = true
        }

        function open(v) {
            var u = (v && v.url) ? v.url.toString() : "";
            if (u === "about:blank")
                u = "";
            originUrl = u;
            suppressQuery = true;
            locationSuggestions.selectedIndex = -1;
            if (locationSuggestions.query !== "")
                locationSuggestions.query = "";
            else
                locationSuggestions.reload();
            isOpen = true;
            Qt.callLater(function () {
                locationInput.text = u;
                Qt.callLater(function () {
                    if (locationInput.inputField) {
                        locationInput.inputField.forceActiveFocus();
                        locationInput.inputField.selectAll();
                    }
                    suppressQuery = false;
                });
            });
        }

        function dismiss() {
            isOpen = false;
        }

        function close() {
            if (!isOpen)
                return;
            newTab = false;
            dismiss();
            var v = webContainer.currentActiveView;
            if (v)
                v.forceActiveFocus();
        }

        function syncQuery() {
            if (suppressQuery || !isOpen)
                return;
            var field = locationInput.inputField;
            var t = locationInput.text;
            var untouched = t === originUrl && field && t !== "" && field.selectedText === t;
            locationSuggestions.selectedIndex = -1;
            var next = untouched ? "" : t.trim();
            if (locationSuggestions.query !== next)
                locationSuggestions.query = next;
        }

        function commit(query) {
            if (newTab) {
                openNewTab(query);
            } else {
                var v = webContainer.currentActiveView;
                if (!v || !browserConfig)
                    return;
                var q = (query !== undefined && query !== null) ? ("" + query) : locationInput.text;
                q = q.trim();
                if (q === "")
                    return;
                v.url = browserConfig.resolveQueryOrUrl(q);
            }
            close();
        }

        function goTo(url) {
            if (newTab) {
                openNewTab(url);
            } else {
                var v = webContainer.currentActiveView;
                if (!v || !url)
                    return;
                v.url = url;
            }
            close();
        }

        function acceptInput(query) {
            if (locationSuggestions.selectedIndex >= 0) {
                locationSuggestions.activateCurrent();
            } else {
                var q = (query !== undefined && query !== null) ? ("" + query) : locationInput.text;
                commit(urlGhost.completed(q));
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.28)
            opacity: locationPopup.openProgress

            MouseArea {
                anchors.fill: parent
                enabled: locationPopup.isOpen
                onClicked: locationPopup.close()
            }
        }

        Item {
            id: locationCard
            width: Math.min(Math.max(320, webContainer.width - 48), 680)
            height: locationCol.implicitHeight + 20
            x: webContainer.x + Math.round((webContainer.width - width) / 2)
            y: {
                var proposed = webContainer.y + Math.round(webContainer.height * 0.28);
                var limit = webContainer.y + webContainer.height - height - 12;
                return Math.max(webContainer.y + 12, Math.min(proposed, limit));
            }
            scale: 0.94 + (locationPopup.openProgress * 0.06)
            opacity: Math.min(1.0, locationPopup.openProgress * 1.8)

            CielSquircle {
                id: locationCardBg
                anchors.fill: parent
                color: Theme.surface
                borderWidth: 1
                borderColor: Theme.border
                radius: 16
                visible: false
            }

            MultiEffect {
                anchors.fill: locationCardBg
                source: locationCardBg
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.18)
                shadowBlur: 0.85
                shadowVerticalOffset: 8
                shadowHorizontalOffset: 0
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                onPressed: mouse => mouse.accepted = true
            }

            ColumnLayout {
                id: locationCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 10
                spacing: 6

                CielSearch {
                    id: locationInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    placeholder: "Search or enter URL"
                    showBorder: false
                    Keys.onPressed: event => urlGhost.handleKey(event)

                    postContent: CielIconButton {
                        icon: "arrow-right"
                        size: Theme.XSMALL
                        onClicked: locationPopup.acceptInput(locationInput.text)
                    }

                    onTextChanged: locationPopup.syncQuery()
                    onAccepted: query => locationPopup.acceptInput(query)
                }

                Item {
                    id: suggestionsWrap
                    Layout.fillWidth: true
                    Layout.preferredHeight: locationSuggestions.implicitHeight + 8 * reveal
                    clip: true

                    readonly property real reveal: Math.max(0, Math.min(1, locationSuggestions.implicitHeight / 40))

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        y: 5 * suggestionsWrap.reveal
                        height: 1
                        color: Theme.border
                        opacity: suggestionsWrap.reveal
                    }

                    UrlCompletionList {
                        id: locationSuggestions
                        anchors.left: parent.left
                        anchors.right: parent.right
                        y: 8 * suggestionsWrap.reveal
                        height: implicitHeight
                        onActivated: url => locationPopup.goTo(url)
                    }
                }
            }

            UrlGhostText {
                id: urlGhost
                target: locationInput
                active: locationPopup.isOpen
                blocked: locationSuggestions.selectedIndex >= 0
            }
        }
    }

    Connections {
        target: webContainer
        function onCurrentActiveViewChanged() {
            if (findBar.isOpen)
                findBar.close();
            if (locationPopup.isOpen)
                locationPopup.dismiss();
        }
    }

    Shortcut {
        sequence: "Ctrl+F"
        onActivated: window.openFind()
    }
    Shortcut {
        sequence: "Ctrl+L"
        context: Qt.ApplicationShortcut
        onActivated: window.openLocation()
    }
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: {
            locationPopup.close();
            findBar.close();
        }
    }
    Shortcut {
        sequence: "Down"
        enabled: locationPopup.isOpen && locationSuggestions.count > 0
        context: Qt.ApplicationShortcut
        onActivated: locationSuggestions.move(1)
    }
    Shortcut {
        sequence: "Up"
        enabled: locationPopup.isOpen && locationSuggestions.count > 0
        context: Qt.ApplicationShortcut
        onActivated: locationSuggestions.move(-1)
    }
    Shortcut {
        sequence: "Shift+Return"
        enabled: findBar.isOpen
        onActivated: findBar.run(true)
    }

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

        property var contextRequest: null

        CielMenuItem {
            text: "Back"
            icon: "arrow-left"
            visible: webContainer.currentActiveView ? webContainer.currentActiveView.canGoBack : false
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.goBack();
                }
                webContextMenu.close();
            }
        }
        CielMenuItem {
            text: "Forward"
            icon: "arrow-right"
            visible: webContainer.currentActiveView ? webContainer.currentActiveView.canGoForward : false
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.goForward();
                }
                webContextMenu.close();
            }
        }
        CielMenuItem {
            text: "Reload"
            icon: "arrow-clockwise"
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.reload();
                }
                webContextMenu.close();
            }
        }

        CielMenuSeparator {
            visible: (webContextMenu.contextRequest?.selectedText !== "")
        }

        CielMenuItem {
            text: {
                const txt = webContextMenu.contextRequest?.selectedText || "";
                return "Search " + browserSettings.engineLabel() + " for \"" + txt.substring(0, 8) + (txt.length > 8 ? "..." : "") + "\"";
            }
            icon: "magnifying-glass"
            visible: webContextMenu.contextRequest?.selectedText !== ""
            onTriggered: {
                if (workspaceContainer.wsTabModel && webContextMenu.contextRequest?.selectedText) {
                    workspaceContainer.wsTabModel.addTab(browserSettings.searchUrl(webContextMenu.contextRequest.selectedText));
                }
                webContextMenu.close();
            }
        }

        CielMenuSeparator {
            visible: (webContextMenu.contextRequest?.linkUrl !== "") || (webContextMenu.contextRequest?.selectedText !== "")
        }

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

        CielMenuSeparator {
            visible: webContextMenu.contextRequest?.mediaType === 2
        }

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

        CielMenuItem {
            text: "View page source"
            onTriggered: {
                if (webContainer.currentActiveView) {
                    webContainer.currentActiveView.triggerWebAction(WebEngineView.ViewSource);
                }
                webContextMenu.close();
            }
        }
    }

    CielPopup {
        id: jsDialogPopup

        contentWidth: 380

        contentHeight: dialogColumn.implicitHeight + 40

        property var dialogRequest: null
        property string dialogMessage: ""
        property string dialogTitle: "Message"
        property int dialogType: 0
        property string dialogDefaultText: ""

        property bool _requestResolved: false

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
            spacing: 12

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
                Layout.maximumHeight: 200
            }

            CielInput {
                id: promptInput
                visible: jsDialogPopup.dialogType === 2
                text: jsDialogPopup.dialogDefaultText
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                placeholder: "Enter text..."

                onVisibleChanged: {
                    if (visible) {
                        Qt.callLater(function () {
                            if (promptInput.inputField) {
                                promptInput.inputField.forceActiveFocus();
                                promptInput.inputField.selectAll();
                            }
                        });
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        event.accepted = true;
                        okButton.onClicked();
                    }
                }
            }

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

    FileDialog {
        id: printDialog
        title: "Save page as PDF"
        fileMode: FileDialog.SaveFile
        nameFilters: ["PDF documents (*.pdf)"]

        property var printView: null

        onAccepted: {
            if (printView) {
                printView.printToPdf(window.localPathFromUrl(selectedFile));
            }
            printView = null;
        }
        onRejected: printView = null
    }

    Connections {
        target: webContainer.currentActiveView
        ignoreUnknownSignals: true
        function onPdfPrintingFinished(filePath, success) {
            if (!success)
                console.warn("[print] failed to write PDF:", filePath);
        }
    }

    FileDialog {
        id: saveDialog
        title: "Save page as"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Web page, complete (*.html)", "Web page, HTML only (*.html)", "Web page, single file (*.mhtml)"]

        property var saveView: null

        onAccepted: {
            if (!saveView)
                return;
            var formats = [WebEngineDownloadRequest.CompleteHtmlSaveFormat, WebEngineDownloadRequest.SingleHtmlSaveFormat, WebEngineDownloadRequest.MimeHtmlSaveFormat];
            var idx = selectedNameFilter.index;
            var path = window.localPathFromUrl(selectedFile);

            var wantExt = idx === 2 ? ".mhtml" : ".html";
            if (!/\.(html?|mhtml)$/i.test(path))
                path += wantExt;

            var slash = path.lastIndexOf("/");
            windowManager.pendingSave = {
                dir: path.substring(0, slash),
                name: path.substring(slash + 1),
                format: formats[idx]
            };
            saveView.triggerWebAction(WebEngineView.SavePage);
            saveView = null;
        }
        onRejected: saveView = null
    }

    Shortcut {
        sequence: "Ctrl+S"
        onActivated: window.savePageCurrent()
    }

    CielPopup {
        id: translatePopup
        contentWidth: 360
        contentHeight: 190

        property string targetUrl: ""
        property var targetView: null

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            Text {
                text: "Translate Page"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                color: Theme.textPrimary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "Translate to:"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: Theme.textPrimary
                    Layout.alignment: Qt.AlignVCenter
                }

                CielSelect {
                    id: translateSelect
                    Layout.fillWidth: true
                    model: window.translateLanguages.map(function (l) {
                        return l.name;
                    })
                    currentIndex: 0
                }
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item {
                    Layout.fillWidth: true
                }

                CielButton {
                    text: "Cancel"
                    onClicked: translatePopup.close()
                }

                CielButton {
                    text: "Translate"
                    primary: true
                    onClicked: {
                        var lang = window.translateLanguages[translateSelect.currentIndex].code;
                        if (translatePopup.targetView)
                            translatePopup.targetView.url = window.translateUrl(translatePopup.targetUrl, lang);
                        translatePopup.targetView = null;
                        translatePopup.close();
                    }
                }
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+P"
        onActivated: window.printCurrentPage()
    }

    onClosing: function (close) {
        if (!allowClose && browserSettings.confirmClose) {
            var model = workspaceModel.tabModel(workspaceModel.currentWorkspaceId);
            if (model && model.count > 1) {
                close.accepted = false;
                closeConfirmPopup.open();
                return;
            }
        }
        if (windowManager)
            windowManager.windowClosed(window);
    }
    onActiveChanged: if (active && windowManager)
        windowManager.currentWindow = window

    CielPopup {
        id: closeConfirmPopup
        contentWidth: 360
        contentHeight: 168

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Text {
                text: "Close this window?"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: Theme.textPrimary
            }

            Text {
                text: "More than one tab is still open."
                font.pixelSize: 13
                color: Theme.textSecondary
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                CielButton {
                    text: "Cancel"
                    onClicked: closeConfirmPopup.close()
                }

                CielButton {
                    text: "Close"
                    primary: true
                    onClicked: {
                        window.allowClose = true;
                        closeConfirmPopup.close();
                        window.close();
                    }
                }
            }
        }
    }

    Connections {
        target: tabRail
        function onCollapsedChanged() {
            if (browserSettings.sidebarCollapsed !== tabRail.collapsed)
                browserSettings.sidebarCollapsed = tabRail.collapsed;
        }
    }

    Connections {
        target: browserSettings
        function onSidebarCollapsedChanged() {
            if (tabRail.collapsed !== browserSettings.sidebarCollapsed)
                tabRail.collapsed = browserSettings.sidebarCollapsed;
        }
        function onSpellCheckEnabledChanged() {
            window.applyProfileSettings();
        }
        function onUserAgentPresetChanged() {
            window.applyProfileSettings();
            if (!window.profileReady)
                return;
            var v = webContainer.currentActiveView;
            if (v && v.visible && v.reload)
                v.reload();
        }
    }

    Component.onCompleted: {
        tabRail.collapsed = browserSettings.sidebarCollapsed;
        Qt.callLater(function () {
            window.applyProfileSettings();
            window.profileReady = true;
        });
    }

    Shortcut {
        sequence: "Ctrl+T"
        onActivated: window.openLocation("new")
    }
    Shortcut {
        sequence: "Ctrl+,"
        onActivated: window.openSettings()
    }
    Shortcut {
        sequence: "Ctrl+N"
        onActivated: window.windowManager.openWindow({
            privateMode: window.isPrivate
        })
    }
    Shortcut {
        sequence: "Ctrl+Shift+N"
        onActivated: window.windowManager.openWindow({
            privateMode: true
        })
    }
    Shortcut {
        sequence: "Ctrl+Shift+O"
        onActivated: openBookmarksTab()
    }
    Shortcut {
        sequence: "Ctrl+Shift+T"
        onActivated: window.restoreClosedTab()
    }
    Shortcut {
        sequence: "Ctrl+H"
        onActivated: window.openHistoryTab()
    }
    Shortcut {
        sequence: "Ctrl+J"
        onActivated: tabRail.downloadsPopup.open()
    }
    Shortcut {
        sequence: "Ctrl+Q"
        onActivated: Qt.quit()
    }
    Shortcut {
        sequence: "Ctrl+R"
        onActivated: webContainer.currentActiveView.reload()
    }
    Shortcut {
        sequence: "Ctrl+B"
        onActivated: tabRail.collapsed = !tabRail.collapsed
    }
}
