import QtQuick
import qs.Commons

// A small caption above a settings field.
Text {
  property string fontFamily: Style.font.family

  textFormat: Text.PlainText
  color: Util.alpha(Color.popups.text, 0.7)
  font.family: fontFamily
  font.pixelSize: Style.font.bodySmall
  font.bold: true
}
