import QtQuick
import qs.Commons
import qs.Commons as Commons

// A big choice card: a glyph, a title and one line on what it holds.
MouseArea {
  id: root

  property string glyph: ""
  property string title: ""
  property string description: ""
  property string fontFamily: Style.font.family

  implicitHeight: Math.max(Style.space(64), texts.implicitHeight + Style.space(28))
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  Accessible.role: Accessible.Button
  Accessible.name: title

  Rectangle {
    anchors.fill: parent
    radius: Style.space(12)
    color: root.containsMouse ? Util.alpha(Commons.Color.popups.text, 0.07) : Util.alpha(Commons.Color.popups.text, 0.04)
    border.width: 1
    border.color: root.containsMouse ? Commons.Color.accent : Util.alpha(Commons.Color.popups.text, 0.1)
    transform: Translate { y: root.containsMouse ? -Style.space(2) : 0 }

    Behavior on border.color { ColorAnimation { duration: Style.duration(200) } }
  }

  Rectangle {
    id: tile

    x: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(40)
    height: width
    radius: Style.space(10)
    color: Util.alpha(Commons.Color.accent, 0.15)

    Text { anchors.centerIn: parent; text: root.glyph; textFormat: Text.PlainText; color: Commons.Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.title }
  }

  Column {
    id: texts

    anchors.left: tile.right
    anchors.leftMargin: Style.space(14)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Text { width: parent.width; text: root.title; textFormat: Text.PlainText; color: Commons.Color.popups.text; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
    Text { width: parent.width; text: root.description; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Util.alpha(Commons.Color.popups.text, 0.65); font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
  }
}
