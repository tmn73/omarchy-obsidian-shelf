import QtQuick
import qs.Commons

// The sync in one card: on, the next setup step, or off.
Rectangle {
  id: root

  property var guide: null
  property string syncedAt: ""
  property string fontFamily: Style.font.family

  signal guideToggled(bool on)

  readonly property bool active: guide !== null && guide.active
  readonly property bool running: active && guide.running
  readonly property var step: active ? guide.step : null

  implicitHeight: body.implicitHeight + Style.space(24)
  radius: Style.space(10)
  color: Util.alpha(Color.popups.text, 0.04)
  border.width: 1
  border.color: Util.alpha(Color.popups.text, 0.1)

  Column {
    id: body

    x: Style.space(12)
    y: Style.space(12)
    width: parent.width - Style.space(24)
    spacing: Style.space(5)

    SettingsCaption { text: qsTr("SYNC"); fontFamily: root.fontFamily }

    Row {
      spacing: Style.space(6)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(7)
        height: width
        radius: width / 2
        color: root.running ? Color.accent : (root.step ? Color.urgent : Util.alpha(Color.popups.text, 0.4))
      }

      Text {
        text: root.running ? qsTr("Obsidian Sync on") : (root.step ? qsTr(root.step.title) : qsTr("Not guided"))
        textFormat: Text.PlainText
        color: Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Text {
      width: parent.width
      text: root.running ? qsTr("synced %1").arg(root.syncedAt) : (root.step ? qsTr("Finish it from the shelf") : qsTr("Your own sync, or none"))
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Util.alpha(Color.popups.text, 0.65)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      width: toggleLabel.implicitWidth
      height: toggleLabel.implicitHeight
      cursorShape: Qt.PointingHandCursor
      onClicked: root.guideToggled(!root.active)

      Text { id: toggleLabel; text: root.active ? qsTr("I sync another way") : qsTr("Use Obsidian Sync"); textFormat: Text.PlainText; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    }
  }
}
