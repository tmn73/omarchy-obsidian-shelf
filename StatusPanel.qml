import QtQuick
import qs.Commons
import qs.Ui

// The status menu under a card: every lane of the board, the current one
// marked, and a field to make a new status. It takes the focus, so Escape
// closes it while the popup keys are off.
FocusScope {
  id: root

  property var lanes: []
  property string current: ""
  property string fontFamily: Style.font.family
  property bool naming: false

  signal picked(string lane)
  signal created(string lane)
  signal cancelled()

  implicitHeight: frame.height

  Component.onCompleted: forceActiveFocus()
  Keys.onEscapePressed: root.cancelled()
  onNamingChanged: if (naming) nameField.forceActiveFocus()

  Rectangle {
    id: frame

    width: parent.width
    height: body.implicitHeight + Style.space(20)
    radius: Style.space(10)
    color: Util.alpha(Color.popups.text, 0.06)
    border.width: 1
    border.color: Util.alpha(Color.popups.text, 0.14)

    Column {
      id: body

      x: Style.space(10)
      y: Style.space(10)
      width: parent.width - Style.space(20)
      spacing: Style.space(8)

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.lanes.concat([""])

          delegate: MouseArea {
            id: chip

            required property string modelData
            readonly property bool isNew: modelData === ""
            readonly property bool isCurrent: modelData === root.current

            width: chipLabel.implicitWidth + Style.space(20)
            height: Style.space(32)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            Accessible.role: Accessible.Button
            Accessible.name: isNew ? qsTr("New status") : qsTr("Move to %1").arg(modelData)
            onClicked: {
              if (isNew)
                root.naming = true
              else
                root.picked(modelData)
            }

            Rectangle {
              anchors.fill: parent
              radius: Style.space(7)
              color: chip.isCurrent ? Color.accent : chip.containsMouse ? Util.alpha(Color.popups.text, 0.14) : Util.alpha(Color.popups.text, 0.07)
              border.width: chip.isNew ? 1 : 0
              border.color: Util.alpha(Color.popups.text, 0.3)
            }

            Text {
              id: chipLabel

              anchors.centerIn: parent
              text: chip.isNew ? qsTr("+ New status") : chip.modelData
              textFormat: Text.PlainText
              color: chip.isCurrent ? Color.popups.background : Color.popups.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: chip.isCurrent
            }
          }
        }
      }

      TextField {
        id: nameField

        visible: root.naming
        width: parent.width
        placeholderText: qsTr("Name of the new status, then Enter")
        font.family: root.fontFamily
        onAccepted: if (text.trim() !== "") root.created(text.trim())
        Keys.onEscapePressed: root.cancelled()
      }

      Text {
        width: parent.width
        text: qsTr("A new status is a new lane of the board, before Done. The phone shows it too.")
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        visible: root.naming
        color: Util.alpha(Color.popups.text, 0.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
