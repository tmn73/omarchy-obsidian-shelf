import QtQuick
import qs.Commons

// Title, sync line and the settings button.
Item {
  id: root

  property string syncText: ""
  property bool failing: false
  property bool settingsOpen: false
  property string fontFamily: Style.font.family

  signal settingsToggled()

  implicitHeight: Math.max(titleBlock.implicitHeight, gear.height)

  Column {
    id: titleBlock

    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Text {
      text: "SHELF"
      textFormat: Text.PlainText
      color: Color.popups.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      font.letterSpacing: Style.space(2)
    }

    Row {
      spacing: Style.space(6)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(6)
        height: width
        radius: width / 2
        color: root.failing ? Color.urgent : Color.accent
      }

      Text {
        text: root.syncText
        textFormat: Text.PlainText
        color: root.failing ? Color.urgent : Util.alpha(Color.popups.text, 0.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.width - gear.width - Style.space(24))
      }
    }
  }

  MouseArea {
    id: gear

    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(34)
    height: width
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.settingsToggled()

    Rectangle {
      anchors.fill: parent
      radius: Style.space(8)
      color: gear.containsMouse || root.settingsOpen ? Util.alpha(Color.popups.text, 0.1) : "transparent"

      Behavior on color { ColorAnimation { duration: Style.duration(150) } }
    }

    Text {
      anchors.centerIn: parent
      text: root.settingsOpen ? "" : ""
      textFormat: Text.PlainText
      color: Color.popups.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
  }
}
