import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Vault folder, refresh interval, sync check and the list editor. Every
// change goes out through settingChanged; Panel.qml is the only place that
// persists it.
FocusScope {
  id: root

  property var config: ({ vaultPath: "", refreshIntervalSec: 10, syncCheckCommand: "", lists: [], errors: [] })
  property string fontFamily: Style.font.family
  readonly property bool inputFocused: activeFocus

  signal settingChanged(string name, var value)

  property string suggestedVault: ""

  implicitHeight: form.implicitHeight

  function emitLists(lists) {
    root.settingChanged("lists", lists)
  }

  function replaceList(index, entry) {
    var lists = root.config.lists.slice()
    lists[index] = entry
    emitLists(lists)
  }

  function removeList(index) {
    var lists = root.config.lists.slice()
    lists.splice(index, 1)
    emitLists(lists)
  }

  function addList() {
    var lists = root.config.lists.slice()
    var n = lists.length + 1
    var ids = lists.map(function (l) { return l.id })
    while (ids.indexOf("list-" + n) >= 0)
      n++
    lists.push({ id: "list-" + n, name: qsTr("List %1").arg(n), type: "checklist", path: "List " + n + ".md", badge: true, onDone: "delete" })
    emitLists(lists)
  }

  // The vault Obsidian has open, read from its own registry, as a suggestion.
  FileView {
    path: Quickshell.env("HOME") + "/.config/obsidian/obsidian.json"
    onLoaded: {
      try {
        var vaults = JSON.parse(text()).vaults || {}
        var paths = Object.keys(vaults).map(function (k) { return vaults[k] })
        var open = paths.filter(function (v) { return v.open })[0] || paths[0]
        root.suggestedVault = open && open.path ? String(open.path) : ""
      } catch (e) {
        root.suggestedVault = ""
      }
    }
  }

  Column {
    id: form

    width: parent.width
    spacing: Style.space(14)

    Repeater {
      model: root.config.errors

      delegate: Text {
        required property string modelData

        width: form.width
        text: modelData
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    SettingsCaption { text: qsTr("Vault folder"); fontFamily: root.fontFamily }

    TextField {
      width: parent.width
      text: root.config.vaultPath
      placeholderText: qsTr("Folder that holds your lists")
      font.family: root.fontFamily
      onEditingFinished: if (text.trim() !== root.config.vaultPath) root.settingChanged("vaultPath", text.trim())
    }

    Button {
      visible: root.suggestedVault !== "" && root.suggestedVault !== root.config.vaultPath
      text: qsTr("Use the open Obsidian vault: %1").arg(root.suggestedVault)
      onClicked: root.settingChanged("vaultPath", root.suggestedVault)
    }

    NumberField {
      width: parent.width
      label: qsTr("Refresh every (seconds)")
      from: 10
      to: 600
      stepSize: 10
      value: root.config.refreshIntervalSec
      fontFamily: root.fontFamily
      onModified: function (value) { root.settingChanged("refreshIntervalSec", value) }
    }

    SettingsCaption { text: qsTr("Sync check command (optional)"); fontFamily: root.fontFamily }

    TextField {
      width: parent.width
      text: root.config.syncCheckCommand
      placeholderText: "systemctl --user is-active --quiet obsidian-headless.service"
      font.family: root.fontFamily
      onEditingFinished: if (text.trim() !== root.config.syncCheckCommand) root.settingChanged("syncCheckCommand", text.trim())
    }

    Toggle {
      width: parent.width
      label: qsTr("Guide the Obsidian Sync setup")
      description: qsTr("Shows the steps to keep the vault in sync while the Obsidian app is closed.")
      checked: root.config.obsidianSync !== false
      fontFamily: root.fontFamily
      onClicked: root.settingChanged("obsidianSync", !checked)
    }

    Toggle {
      width: parent.width
      label: qsTr("Link previews")
      description: qsTr("A saved link without a picture or title: read its page once for them. Only the site sees it.")
      checked: root.config.linkPreviews !== false
      fontFamily: root.fontFamily
      onClicked: root.settingChanged("linkPreviews", !checked)
    }

    Toggle {
      width: parent.width
      label: qsTr("Tweet previews (fxtwitter.com)")
      description: qsTr("Author picture and first photo of saved tweets. fxtwitter sees the tweet links you save, once per tweet.")
      checked: root.config.tweetPreviews === true
      fontFamily: root.fontFamily
      onClicked: root.settingChanged("tweetPreviews", !checked)
    }

    SettingsCaption { text: qsTr("Lists"); fontFamily: root.fontFamily }

    Repeater {
      model: root.config.lists

      delegate: ListEditorRow {
        required property var modelData
        required property int index

        width: form.width
        entry: modelData
        fontFamily: root.fontFamily
        onEdited: function (entry) { root.replaceList(index, entry) }
        onRemoved: root.removeList(index)
      }
    }

    Button {
      text: qsTr("Add list")
      onClicked: root.addList()
    }
  }
}
