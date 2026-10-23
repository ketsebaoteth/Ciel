import Quickshell
import QtQuick
import QtQuick.Layouts
import Ciel.Ui

// A nested submenu level (second level and deeper). Recursive: it instantiates
// itself for any child entry that has children of its own.
CielMenuSub {
    id: sub

    property var entry: null       // QsMenuEntry that has children
    property var owner: null       // top-level TrayDropDown (for finish())

    text: owner ? owner.cleanText(entry ? entry.text : "") : (entry ? entry.text : "")
    enabled: entry ? entry.enabled : true

    property var menuOpener: QsMenuOpener {
        menu: sub.entry
    }

    Repeater {
        model: sub.menuOpener.children

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
                    text: sub.owner ? sub.owner.cleanText(ld.entry.text) : ld.entry.text
                    icon: sub.owner ? sub.owner.checkIcon(ld.entry) : ""
                    enabled: ld.entry.enabled

                    onTriggered: {
                        ld.entry.triggered();
                        if (sub.owner)
                            sub.owner.finish();
                    }
                }
            }

            Component {
                id: subComp
            
                Loader {
                    source: Qt.resolvedUrl("TrayMenuSub.qml")
            
                    onLoaded: {
                        item.entry = ld.entry
                        item.owner = sub.owner
                    }
                }
            }
        }
    }
}
