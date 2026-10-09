import QtQuick
import qs.Commons
import qs.Commons as Commons

// One line of a picker: a label, a muted detail on the right.
MouseArea {
  id: root

  property string label: ""
  property string detail: ""
  property bool selected: false
  property string fontFamily: Style.font.family

  width: parent ? parent.width : 0
  height: Style.space(34)
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  Accessible.role: Accessible.Button
  Accessible.name: label

  Rectangle {
    anchors.fill: parent
    radius: Style.space(6)
    color: root.selected ? Util.alpha(Commons.Color.accent, 0.15) : (root.containsMouse ? Util.alpha(Commons.Color.popups.text, 0.08) : "transparent")
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.right: detailText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textFormat: Text.PlainText
    elide: Text.ElideMiddle
    color: root.selected ? Commons.Color.accent : Commons.Color.popups.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    id: detailText

    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: root.detail
    textFormat: Text.PlainText
    color: Util.alpha(Commons.Color.popups.text, 0.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
