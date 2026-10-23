import Quickshell
import QtQuick
import QtQuick.Layouts
import Ciel.Ui

// Submenu of one root-level tray entry. Opens to the right of its trigger row.
CielDropDown {
    id: dd

    property var entry: null       // QsMenuEntry that has children
    property var popup: null       // owning TrayPopup

    placement: "right"

    property var menuOpener: QsMenuOpener {
        menu: dd.entry
    }

    // Close this dropdown and the whole tray popup.
    function finish() {
        dd.close();
        if (popup)
            popup.close();
    }

    function cleanText(t) {
        return (t || "").replace(/__/g, "\u0001").replace(/_/g, "").replace(/\u0001/g, "_");
    }

    // CielMenuItem icons are icon-set names, so entry icon URLs can't be used here;
    // checkbox / radio state is shown with a check like the rest of the UI.
    function checkIcon(e) {
        if (!e || e.buttonType === QsMenuButtonType.None)
            return "";
        if (e.checkState === Qt.PartiallyChecked)
            return "minus";
        if (e.checkState === Qt.Checked)
            return "check";
        return "";
    }

    Repeater {
        model: dd.menuOpener.children

        delegate: Loader {
            id: ld

            required property var modelData
            readonly property var entry: modelData

            // The dropdown content is a plain Column (not a layout) and the card is
            // at least 260 wide with 6px margins, so fix the row width explicitly.
            width: 248

            sourceComponent: !entry ? null : (entry.isSeparator ? sepComp : (entry.hasChildren ? subComp : itemComp))

            Component {
                id: sepComp

                Item {
                    implicitHeight: 9

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        height: 1
                        color: Theme.surfaceHover
                    }
                }
            }

            Component {
                id: itemComp

                CielMenuItem {
                    text: dd.cleanText(ld.entry.text)
                    icon: dd.checkIcon(ld.entry)
                    enabled: ld.entry.enabled

                    onTriggered: {
                        ld.entry.triggered();
                        dd.finish();
                    }
                }
            }

            Component {
                id: subComp

                TrayMenuSub {
                    entry: ld.entry
                    owner: dd
                }
            }
        }
    }
}
