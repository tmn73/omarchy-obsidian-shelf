import QtQuick
import qs.Commons
import qs.Ui

// What a new user sees: first the vault (the ones Obsidian knows, one click),
// then an empty shelf that leads to the first list.
Column {
  id: root

  property bool configured: false
  property string fontFamily: Style.font.family
  property var vaults: []

  signal vaultChosen(string path)
  signal addRequested()

  spacing: Style.space(12)
  topPadding: Style.space(8)
  bottomPadding: Style.space(8)

  function load() {
    if (!configured)
      helper.run(["vaults"], function (data) { root.vaults = data.vaults || [] })
  }

  Component.onCompleted: load()
  onConfiguredChanged: load()

  HelperCall { id: helper }

  Text {
    text: root.configured ? "" : ""
    textFormat: Text.PlainText
    color: Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.displayLarge
  }

  Text {
    width: parent.width
    text: root.configured ? qsTr("Your shelf is empty") : qsTr("Where are your notes?")
    textFormat: Text.PlainText
    color: Color.popups.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.heading
    font.bold: true
  }

  Text {
    width: parent.width
    text: root.configured
      ? qsTr("Add a list of links, tasks or notes from your vault. What you capture on your phone then shows up here.")
      : qsTr("Pick the folder that holds your Markdown notes, usually your Obsidian vault.")
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Util.alpha(Color.popups.text, 0.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Column {
    visible: !root.configured
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: root.vaults

      delegate: PickerOption {
        required property var modelData

        label: modelData.name + "  ·  " + modelData.path.replace(/^\/home\/[^/]+/, "~")
        detail: modelData.open ? qsTr("open in Obsidian") : ""
        fontFamily: root.fontFamily
        onClicked: root.vaultChosen(modelData.path)
      }
    }

    TextField {
      width: parent.width
      placeholderText: qsTr("Or type a folder path, then Enter")
      font.family: root.fontFamily
      onAccepted: if (text.trim() !== "") root.vaultChosen(text.trim())
    }
  }

  Button {
    visible: root.configured
    text: qsTr("Add your first list")
    bordered: true
    background: Color.accent
    foreground: Color.popups.background
    onClicked: root.addRequested()
  }
}
