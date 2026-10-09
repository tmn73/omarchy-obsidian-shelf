import QtQuick
import qs.Commons
import qs.Commons as Commons

// The date of a card: late in the urgent color, today in the accent, other
// days in a muted tone.
Rectangle {
  id: root

  property string text: ""
  property string tone: ""
  property string fontFamily: Style.font.family

  implicitWidth: label.implicitWidth + Style.space(16)
  implicitHeight: label.implicitHeight + Style.space(6)
  radius: height / 2
  color: tone === "late" ? Util.alpha(Commons.Color.urgent, 0.16) : tone === "today" ? Util.alpha(Commons.Color.accent, 0.18) : Util.alpha(Commons.Color.popups.text, 0.08)

  Text {
    id: label

    anchors.centerIn: parent
    text: root.text
    textFormat: Text.PlainText
    color: root.tone === "late" ? Commons.Color.urgent : root.tone === "today" ? Commons.Color.accent : Util.alpha(Commons.Color.popups.text, 0.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
