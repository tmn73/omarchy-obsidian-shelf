import QtQuick
import qs.Commons
import qs.Commons as Commons

// The key hints in the popup footer.
Row {
  id: root

  property var hints: [["↵", "open"], ["e", "edit"], ["x", "remove"], ["tab", "switch"], ["a", "add"]]
  property string fontFamily: Style.font.family

  spacing: Style.space(14)

  Repeater {
    model: root.hints

    delegate: Row {
      required property var modelData

      spacing: Style.space(6)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.space(18), keyLabel.implicitWidth + Style.space(8))
        height: Style.space(18)
        radius: Style.space(4)
        color: Util.alpha(Commons.Color.popups.text, 0.08)

        Text {
          id: keyLabel

          anchors.centerIn: parent
          text: modelData[0]
          textFormat: Text.PlainText
          color: Commons.Color.popups.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: modelData[1]
        textFormat: Text.PlainText
        color: Util.alpha(Commons.Color.popups.text, 0.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
