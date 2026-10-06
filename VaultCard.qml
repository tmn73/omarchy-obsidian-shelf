import QtQuick
import qs.Commons
import qs.Ui

// The vault: its name and folder, and Change to pick another vault Obsidian
// knows, or any folder typed in.
Rectangle {
  id: root

  property string vaultPath: ""
  property string fontFamily: Style.font.family
  property bool choosing: false
  property var vaults: []

  signal vaultChosen(string path)

  readonly property string name: vaultPath === "" ? qsTr("No vault yet") : vaultPath.replace(/\/+$/, "").split("/").pop()

  implicitHeight: body.implicitHeight + Style.space(24)
  radius: Style.space(10)
  color: Util.alpha(Color.popups.text, 0.04)
  border.width: 1
  border.color: Util.alpha(Color.popups.text, 0.1)

  onChoosingChanged: if (choosing) helper.run(["vaults"], function (data) { root.vaults = data.vaults || [] })

  HelperCall { id: helper }

  Column {
    id: body

    x: Style.space(12)
    y: Style.space(12)
    width: parent.width - Style.space(24)
    spacing: Style.space(5)

    SettingsCaption { text: qsTr("VAULT"); fontFamily: root.fontFamily }
    Text { width: parent.width; text: root.name; textFormat: Text.PlainText; elide: Text.ElideRight; color: Color.popups.text; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
    Text { width: parent.width; text: root.vaultPath.replace(/^\/home\/[^/]+/, "~"); textFormat: Text.PlainText; elide: Text.ElideMiddle; color: Util.alpha(Color.popups.text, 0.65); font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }

    MouseArea {
      width: changeLabel.implicitWidth
      height: changeLabel.implicitHeight
      cursorShape: Qt.PointingHandCursor
      onClicked: root.choosing = !root.choosing

      Text { id: changeLabel; text: root.choosing ? qsTr("Cancel") : qsTr("Change"); textFormat: Text.PlainText; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    }

    Column {
      visible: root.choosing
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: root.vaults

        delegate: PickerOption {
          required property var modelData

          label: modelData.name
          detail: modelData.open ? qsTr("open in Obsidian") : ""
          selected: modelData.path === root.vaultPath
          fontFamily: root.fontFamily
          onClicked: { root.choosing = false; root.vaultChosen(modelData.path) }
        }
      }

      TextField {
        width: parent.width
        placeholderText: qsTr("Or type a folder path")
        font.family: root.fontFamily
        onAccepted: if (text.trim() !== "") { root.choosing = false; root.vaultChosen(text.trim()) }
      }
    }
  }
}
