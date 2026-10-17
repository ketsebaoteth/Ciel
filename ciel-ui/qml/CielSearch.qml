import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ciel.Ui

Item {
    id: root
    property alias text: inputField.text
    property string placeholder: "search"
    property alias inputField: inputField.inputField
    property bool isPrimary: false
    property bool showBorder: true
    property Item preContent: null
    property Item postContent: null

    implicitWidth: 300
    implicitHeight: 32

    signal accepted(string query)

    CielInput {
        id: inputField
        anchors.fill: parent
        text: text
        placeholder: placeholder
        isPrimary: isPrimary
        showBorder: showBorder

        preContent: root.preContent || _preContent
        postContent: postContent

        onAccepted: query => root.accepted(query)
    }

    Component {
        id: _preContent

        RowLayout {
            id: contentRow
            anchors.fill: parent
            anchors.leftMargin: 4

            Item {
                id: preSlot
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
                CielIcon {
                    icon: "magnifying-glass"
                    size: Theme.XSMALL
                    color: Theme.textSecondary
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }
}
