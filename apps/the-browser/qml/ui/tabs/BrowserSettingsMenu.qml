import QtQuick
import Ciel.Ui
import Ciel.Browser 1.0

CielDropDown {
    id: root

    property BrowserConfig config: null
    property WorkspaceModel workspaceModel: null

    signal newTabRequested
    signal newWindowRequested
    signal newPrivateWindowRequested
    signal restoreTabRequested
    signal historyRequested
    signal downloadsRequested
    signal passwordsRequested
    signal bookmarksRequested
    signal printRequested
    signal savePageRequested
    signal translateRequested
    signal findInPageRequested
    signal settingsRequested
    signal extensionsRequested
    signal sitePermissionsRequested

    CielMenuItem {
        text: "New Tab"
        icon: "plus"
        shortcut: "Ctrl+T"
        onTriggered: {
            root.close();
            root.newTabRequested();
        }
    }

    CielMenuItem {
        text: "New Window"
        icon: "browsers"
        shortcut: "Ctrl+N"
        onTriggered: {
            root.close();
            root.newWindowRequested();
        }
    }

    CielMenuItem {
        text: "New Private Window"
        icon: "detective"
        shortcut: "Ctrl+Shift+N"
        onTriggered: {
            root.close();
            root.newPrivateWindowRequested();
        }
    }

    CielMenuItem {
        text: "Restore Closed Tab"
        icon: "arrow-counter-clockwise"
        shortcut: "Ctrl+Shift+T"
        onTriggered: {
            root.close();
            root.restoreTabRequested();
        }
    }

    CielMenuSeparator {}

    CielMenuItem {
        text: "History"
        icon: "clock-counter-clockwise"
        shortcut: "Ctrl+H"
        onTriggered: {
            root.close();
            root.historyRequested();
        }
    }

    CielMenuItem {
        text: "Passwords"
        icon: "key"
        onTriggered: {
            root.close();
            root.passwordsRequested();
        }
    }

    CielMenuItem {
        text: "Bookmarks"
        icon: "bookmark-simple"
        shortcut: "Ctrl+Shift+O"
        onTriggered: {
            root.close();
            root.bookmarksRequested();
        }
    }

    CielMenuSeparator {}

    CielMenuItem {
        text: "Print…"
        icon: "printer"
        shortcut: "Ctrl+P"
        onTriggered: {
            root.close();
            root.printRequested();
        }
    }

    CielMenuItem {
        text: "Save Page As…"
        icon: "floppy-disk"
        shortcut: "Ctrl+S"
        onTriggered: {
            root.close();
            root.savePageRequested();
        }
    }

    CielMenuItem {
        text: "Translate Page…"
        icon: "translate"
        onTriggered: {
            root.close();
            root.translateRequested();
        }
    }

    CielMenuItem {
        text: "Find in Page"
        icon: "magnifying-glass"
        shortcut: "Ctrl+F"
        onTriggered: {
            root.close();
            root.findInPageRequested();
        }
    }

    CielMenuSeparator {}

    CielMenuItem {
        text: "Extensions"
        icon: "puzzle-piece"
	onTriggered: {
            root.close();
	    root.extensionsRequested()
    	}
    }

    CielMenuItem {
        text: "Site Permissions"
        icon: "shield-check"
	onTriggered: {
            root.close();
	    root.sitePermissionsRequested()
	}
    }

    CielMenuItem {
        text: "Settings"
        icon: "gear-six"
        shortcut: "Ctrl+,"
        onTriggered: {
            root.close();
            root.settingsRequested();
        }
    }

    CielMenuItem {
        text: "Quit"
        icon: "power"
        shortcut: "Ctrl+Q"
        destructive: true
        onTriggered: {
            root.close();
            Qt.quit();
        }
    }
}
