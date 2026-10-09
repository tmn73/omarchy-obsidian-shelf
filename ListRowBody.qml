import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The open part of a list row: name, path with Change…, what a tick does,
// how to add from a phone, and removal.
Column {
  id: root

  property var cfg: ({})
  property string vaultPath: ""
  property string fontFamily: Style.font.family
  property bool picking: false
  property bool showHow: false

  signal changed(string field, var value)
  signal pickingToggled()
  signal howToggled()
  signal removeRequested()

  leftPadding: Style.space(54)
  rightPadding: Style.space(12)
  bottomPadding: Style.space(14)
  spacing: Style.space(10)

  readonly property real innerWidth: width - leftPadding - rightPadding

  Row {
    width: root.innerWidth
    spacing: Style.space(8)

    SettingsCaption { anchors.verticalCenter: parent.verticalCenter; width: Style.space(60); text: qsTr("Name"); fontFamily: root.fontFamily }

    TextField {
      width: parent.width - Style.space(60) - parent.spacing
      text: root.cfg.name || ""
      font.family: root.fontFamily
      onEditingFinished: if (text.trim() !== "" && text.trim() !== root.cfg.name) root.changed("name", text.trim())
    }
  }

  Row {
    width: root.innerWidth
    spacing: Style.space(8)

    SettingsCaption { anchors.verticalCenter: parent.verticalCenter; width: Style.space(60); text: root.cfg.type === "folder" ? qsTr("Folder") : qsTr("File"); fontFamily: root.fontFamily }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(60) - change.width - parent.spacing * 2
      text: root.cfg.path || ""
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      color: Commons.Color.popups.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Button {
      id: change

      text: root.picking ? qsTr("Cancel") : qsTr("Change…")
      bordered: true
      onClicked: root.pickingToggled()
    }
  }

  Loader {
    width: root.innerWidth
    active: root.picking
    visible: active
    sourceComponent: VaultPicker {
      vaultPath: root.vaultPath
      kind: root.cfg.type === "folder" ? "folder" : "file"
      current: root.cfg.path
      fontFamily: root.fontFamily
      onPicked: function (path, isNew) {
        root.changed("path", path)
        root.pickingToggled()
      }
    }
  }

  Row {
    visible: root.cfg.type === "checklist"
    width: root.innerWidth
    spacing: Style.space(8)

    SettingsCaption { anchors.verticalCenter: parent.verticalCenter; width: Style.space(90); text: qsTr("When ticked"); fontFamily: root.fontFamily }

    ButtonGroup {
      options: [{ value: "delete", label: qsTr("remove the line") }, { value: "check", label: qsTr("write [x]") }]
      value: root.cfg.onDone || "delete"
      fontFamily: root.fontFamily
      onChanged: function (value) { root.changed("onDone", value) }
    }
  }

  Toggle {
    visible: root.cfg.type === "board"
    width: root.innerWidth
    label: qsTr("Remind me")
    description: qsTr("A card with a time rings at that time; the others are in the morning summary.")
    checked: root.cfg.remind !== false
    fontFamily: root.fontFamily
    onClicked: root.changed("remind", !(root.cfg.remind !== false))
  }

  Text {
    visible: root.cfg.type === "sections" || root.cfg.type === "board"
    width: root.innerWidth
    text: root.cfg.type === "board"
      ? qsTr("Lanes are the ## headings of the board. Add or rename them in Obsidian.")
      : qsTr("Sections are the ## headings of the file. Add or rename them in the file.")
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Util.alpha(Commons.Color.popups.text, 0.65)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Row {
    width: root.innerWidth

    MouseArea {
      width: howLabel.implicitWidth
      height: howLabel.implicitHeight
      cursorShape: Qt.PointingHandCursor
      onClicked: root.howToggled()

      Text { id: howLabel; text: qsTr("Add from your phone: how"); textFormat: Text.PlainText; color: Commons.Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    }

    Item { width: root.innerWidth - howLabel.implicitWidth - removeLabel.implicitWidth; height: 1 }

    MouseArea {
      width: removeLabel.implicitWidth
      height: removeLabel.implicitHeight
      cursorShape: Qt.PointingHandCursor
      onClicked: root.removeRequested()

      Text { id: removeLabel; text: qsTr("Remove from shelf"); textFormat: Text.PlainText; color: Commons.Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    }
  }

  Rectangle {
    visible: root.showHow
    width: root.innerWidth
    height: how.implicitHeight + Style.space(20)
    radius: Style.space(8)
    color: Util.alpha(Commons.Color.accent, 0.08)
    border.width: 1
    border.color: Util.alpha(Commons.Color.accent, 0.3)

    Text {
      id: how

      x: Style.space(12)
      y: Style.space(10)
      width: parent.width - Style.space(24)
      text: Model.phoneHowTo(root.cfg)
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Util.alpha(Commons.Color.popups.text, 0.8)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
