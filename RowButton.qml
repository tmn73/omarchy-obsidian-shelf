import QtQuick
import qs.Commons

// A square icon button for row actions. `primary` fills with the accent on
// hover, for the action that finishes the item; `danger` turns the urgent
// color on hover, for the action that deletes it.
MouseArea {
  id: root

  property string glyph: ""
  property string label: ""
  property bool primary: false
  property bool danger: false
  property string fontFamily: Style.font.family

  width: Style.space(34)
  height: width
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  Accessible.role: Accessible.Button
  Accessible.name: label

  Rectangle {
    anchors.fill: parent
    radius: Style.space(8)
    scale: root.containsMouse && root.primary ? 1.06 : 1
    color: !root.containsMouse ? "transparent" : root.danger ? Util.alpha(Color.urgent, 0.18) : root.primary ? Color.accent : Util.alpha(Color.popups.text, 0.12)

    Behavior on color { ColorAnimation { duration: Style.duration(150) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic } }
  }

  Text {
    anchors.centerIn: parent
    text: root.glyph
    textFormat: Text.PlainText
    color: root.containsMouse && root.danger ? Color.urgent : root.containsMouse && root.primary ? Color.popups.background : Util.alpha(Color.popups.text, root.containsMouse ? 1 : 0.65)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
