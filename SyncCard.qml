import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The next Obsidian Sync setup step, with one button to take it.
Rectangle {
  id: root

  property var guide: null
  property string fontFamily: Style.font.family

  signal hideRequested()

  readonly property var step: guide ? guide.step : null
  readonly property bool warnDesktop: guide ? (guide.syncState === "unlinked" || guide.syncState === "stopped") : false

  implicitHeight: body.implicitHeight + Style.space(28)
  radius: Style.space(10)
  color: Util.alpha(Commons.Color.accent, 0.08)
  border.width: Math.max(1, Style.space(1))
  border.color: Util.alpha(Commons.Color.accent, 0.35)

  Column {
    id: body

    x: Style.space(14)
    y: Style.space(14)
    width: parent.width - Style.space(28)
    spacing: Style.space(8)

    Row {
      width: parent.width

      Text {
        width: parent.width - hide.width
        text: qsTr("Obsidian Sync on this PC")
        textFormat: Text.PlainText
        color: Util.alpha(Commons.Color.popups.text, 0.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: Style.space(1)
      }

      MouseArea {
        id: hide

        width: hideLabel.implicitWidth
        height: hideLabel.implicitHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: root.hideRequested()

        Text {
          id: hideLabel

          text: qsTr("Hide")
          textFormat: Text.PlainText
          color: Util.alpha(Commons.Color.popups.text, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.underline: hide.containsMouse
        }
      }
    }

    Text {
      width: parent.width
      text: root.step ? qsTr(root.step.title) : ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Commons.Color.popups.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Text {
      width: parent.width
      text: root.step ? qsTr(root.step.text) : ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Util.alpha(Commons.Color.popups.text, 0.75)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      width: parent.width
      visible: root.warnDesktop
      text: qsTr("Pause Sync in the Obsidian app on this PC (Settings, Sync, Pause), so that only one client writes the folder. The app still opens and edits the vault.")
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      width: parent.width
      visible: root.guide && root.guide.message !== ""
      text: root.guide ? root.guide.message : ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Button {
      bordered: true
      background: Commons.Color.accent
      foreground: Commons.Color.popups.background
      text: root.step ? qsTr(root.step.button) : ""
      onClicked: if (root.guide) root.guide.runSyncStep()
    }
  }
}
