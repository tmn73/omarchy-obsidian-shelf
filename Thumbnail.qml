import QtQuick
import Quickshell.Widgets
import qs.Commons

// The picture of a saved link, rounded, or the platform glyph while it loads,
// when it fails, or when the note has none. Videos get a small play mark.
ClippingRectangle {
  id: root

  property string source: ""
  property string glyph: ""
  property bool video: false
  property bool round: false
  property string fontFamily: Style.font.family

  readonly property bool hasPicture: picture.status === Image.Ready

  radius: round ? width / 2 : Style.space(9)
  color: Util.alpha(Color.popups.text, 0.08)

  Text {
    anchors.centerIn: parent
    visible: !root.hasPicture
    text: root.glyph
    textFormat: Text.PlainText
    color: Color.popups.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.title
  }

  Image {
    id: picture

    anchors.fill: parent
    source: root.source
    asynchronous: true
    cache: true
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: width * 2
    sourceSize.height: height * 2
    opacity: root.hasPicture ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: Style.duration(250) } }
  }

  Rectangle {
    visible: root.video && root.hasPicture
    anchors.centerIn: parent
    width: Style.space(26)
    height: width
    radius: width / 2
    color: Util.alpha(Color.popups.background, 0.75)

    Text {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: Style.space(1)
      text: ""
      textFormat: Text.PlainText
      color: Color.popups.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
