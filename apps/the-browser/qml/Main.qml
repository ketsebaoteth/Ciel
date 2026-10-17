import QtQuick
import Ciel.Browser 1.0
import "ui/window"

QtObject {
    id: manager

    property var windows: []
    property var currentWindow: null
    property var pendingSave: null
    property var profileCache: ({})
    property var privateProfileObj: null

    property Component windowComponent: Component {
        BrowserWindow {}
    }

    function openWindow(opts) {
        opts = opts || {};
        var props = {
            windowManager: manager,
            isPrivate: !!opts.privateMode,
            isPrimary: !!opts.primary,
            initialUrl: opts.url ? opts.url.toString() : ""
        };
        if (currentWindow && !opts.primary) {
            props.x = currentWindow.x + 32;
            props.y = currentWindow.y + 32;
            props.width = currentWindow.width;
            props.height = currentWindow.height;
        }

        var w = windowComponent.createObject(manager, props);
        if (!w) {
            console.warn("[windows] failed to create window:", windowComponent.errorString());
            return null;
        }
        windows = windows.concat([w]);
        currentWindow = w;
        return w;
    }

    function windowClosed(w) {
        windows = windows.filter(function (x) {
            return x !== w;
        });
        if (currentWindow === w)
            currentWindow = windows.length > 0 ? windows[windows.length - 1] : null;
        w.destroy(200);
        if (w.isPrivate)
            privateCleanup.restart();
    }

    property Connections profileWatch: Connections {
        target: ProfileManager
        function onActiveProfileAboutToChange() {
            var victims = manager.windows.filter(function (w) {
                return !w.isPrimary && !w.isPrivate;
            });
            for (var i = 0; i < victims.length; ++i)
                victims[i].close();
        }
    }

    Component.onCompleted: openWindow({
        primary: true
    })

    function profileSource(props) {
        return `
            import QtWebEngine
            WebEngineProfile {
                ${props}
                onDownloadRequested: function(download) {
                    manager.handleDownload(download)
                }
            }`;
    }

    function profileFor(profileId) {
        if (profileCache[profileId])
            return profileCache[profileId];

        var storage = ProfileManager.webEngineStoragePathFor(profileId);
        var p = Qt.createQmlObject(profileSource(`
                storageName: "ciel-${profileId}"
                offTheRecord: false
                persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
                persistentStoragePath: "${storage}"
                cachePath: "${storage}/cache"
                httpCacheType: WebEngineProfile.DiskHttpCache`), manager, "profile-" + profileId);
    	profileCache[profileId] = p
        ExtensionManager.attachProfile(profileId, p)
        return p}

    function privateProfile() {
        if (!privateProfileObj) {
            privateProfileObj = Qt.createQmlObject(profileSource("offTheRecord: true"), manager, "profile-private");
        }
        return privateProfileObj;
    }

    property Timer privateCleanup: Timer {
        interval: 1500
        onTriggered: {
            var any = manager.windows.some(function (w) {
                return w.isPrivate;
            });
            if (!any && manager.privateProfileObj) {
                manager.privateProfileObj.destroy();
                manager.privateProfileObj = null;
            }
        }
    }

    function handleDownload(download) {
        if (download.isSavePageDownload) {
            var ps = pendingSave;
            pendingSave = null;
            if (ps) {
                download.downloadDirectory = ps.dir;
                download.downloadFileName = ps.name;
                download.savePageFormat = ps.format;
                download.accept();
            } else {
                download.cancel();
            }
            return;
        }

        var urlStr = download.url ? download.url.toString() : "";
        if (urlStr.startsWith("blob:") || urlStr.startsWith("data:")) {
            download.accept();
            return;
        }

        var target = download.url;
        var name = download.downloadFileName;
        var mime = download.mimeType;
        download.cancel();
        if (currentWindow)
            currentWindow.startDownload(target, name, mime);
    }
}
