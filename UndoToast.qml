import QtQuick
import qs.Commons

// A short message with an Undo button, and an optional second action. It
// leaves by itself after six seconds.
Rectangle {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  property bool shown: false
  property bool undoable: true
  property string actionLabel: ""

  signal undo()
  signal action()

  function show(message, label, canUndo) {
    text = message
    actionLabel = label || ""
    undoable = canUndo !== false
    shown = true
    hideTimer.restart()
  }

  visible: shown
  implicitHeight: label.implicitHeight + Style.space(24)
  radius: Style.space(10)
  color: Util.alpha(Color.popups.text, 0.12)

  Timer {
    id: hideTimer

    interval: 6000
    onTriggered: root.shown = false
  }

  Text {
    id: label

    anchors.left: parent.left
    anchors.leftMargin: Style.space(14)
    anchors.right: buttons.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: root.text
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Color.popups.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Row {
    id: buttons

    anchors.right: parent.right
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(14)

    MouseArea {
      visible: root.actionLabel !== ""
      width: actionText.implicitWidth
      height: actionText.implicitHeight
      cursorShape: Qt.PointingHandCursor
      onClicked: { root.shown = false; root.action() }

      Text { id: actionText; text: root.actionLabel; textFormat: Text.PlainText; color: Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.body }
    }

    MouseArea {
      visible: root.undoable
      width: undoLabel.implicitWidth
      height: undoLabel.implicitHeight
      cursorShape: Qt.PointingHandCursor
      onClicked: { root.shown = false; root.undo() }

      Text { id: undoLabel; text: qsTr("Undo"); textFormat: Text.PlainText; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
    }
  }
}
