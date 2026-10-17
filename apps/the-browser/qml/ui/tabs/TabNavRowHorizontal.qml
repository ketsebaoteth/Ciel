import QtQuick
import QtQuick.Layouts
import Ciel.Ui
import Ciel.Browser 1.0

Item {
    id: root

    property var activeView: null
    required property BrowserConfig config

    implicitHeight: 42

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

    TextEdit {
        id: clipHelper
        visible: false
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 6

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

        CielInput {
            id: omniboxHorizontal
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            placeholder: "Search or enter URL"

            readonly property string fullUrlStr: (root.activeView && root.activeView.url) ? root.activeView.url.toString() : ""

            text: {
                if (omniboxHorizontal.isInputActive) {
                    return fullUrlStr === "about:blank" ? "" : fullUrlStr;
                }
                return root.cleanDisplayUrl(fullUrlStr);
            }

            onAccepted: query => {
                if (root.activeView) {
                    root.activeView.url = root.config.resolveQueryOrUrl(query);
                    omniboxHorizontal.inputField.focus = false;
                }
            }

            preContent: CielIconButton {
                id: linkBtnHorizontal
                property bool copied: false
                icon: copied ? "check" : "link"
                size: Theme.XSMALL
                iconColor: copied ? Theme.accent : Theme.textSecondary

                Timer {
                    id: copyResetTimerHorizontal
                    interval: 1500
                    onTriggered: linkBtnHorizontal.copied = false
                }

                onClicked: {
                    if (root.activeView && root.activeView.url) {
                        clipHelper.text = root.activeView.url.toString();
                        clipHelper.selectAll();
                        clipHelper.copy();
                        linkBtnHorizontal.copied = true;
                        copyResetTimerHorizontal.restart();
                    }
                }
            }

            postContent: RowLayout {
                spacing: 2

                CielIconButton {
                    id: starBtnHorizontal
                    property bool bookmarked: (root.activeView && root.activeView.url) ? ProfileManager.isBookmarked(root.activeView.url.toString()) : false
                    icon: bookmarked ? "star-fill" : "star"
                    size: Theme.XSMALL
                    iconColor: bookmarked ? Theme.accent : Theme.textSecondary

                    Connections {
                        target: ProfileManager
                        function onBookmarksChanged() {
                            if (root.activeView && root.activeView.url) {
                                starBtnHorizontal.bookmarked = ProfileManager.isBookmarked(root.activeView.url.toString());
                            }
                        }
                    }

                    onClicked: {
                        if (root.activeView && root.activeView.url) {
                            var u = root.activeView.url.toString();
                            var t = root.activeView.title ? root.activeView.title : u;
                            starBtnHorizontal.bookmarked = ProfileManager.toggleBookmark(u, t);
                        }
                    }
                }

                CielIconButton {
                    icon: "faders-horizontal"
                    size: Theme.XSMALL
                }
            }
        }
    }
}
