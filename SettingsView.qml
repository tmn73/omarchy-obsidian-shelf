import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The settings page: vault and sync, the lists in tab order, previews and the
// refresh rate. Every change goes out through settingChanged; Panel.qml is the
// only place that persists it.
FocusScope {
  id: root

  property var config: ({ vaultPath: "", refreshIntervalSec: 10, lists: [], errors: [] })
  property var payload: null
  property var syncGuide: null
  property string fontFamily: Style.font.family
  property string expandedId: ""
  property var removed: null
  readonly property bool inputFocused: activeFocus

  signal settingChanged(string name, var value)
  signal addListRequested()

  implicitHeight: form.implicitHeight

  function setLists(lists) {
    root.settingChanged("lists", lists)
  }

  function remove(cfg) {
    var result = Model.removeList(root.config.lists, cfg.id)
    root.removed = result
    root.expandedId = ""
    setLists(result.lists)
    toast.show(qsTr("%1 left the shelf. %2 stays in the vault.").arg(cfg.name).arg(cfg.path), Model.trashLabel(cfg, root.payload))
  }

  // The second action of the toast: the file goes to the trash of the vault,
  // where Obsidian keeps its deleted files.
  function trashRemoved() {
    if (!root.removed || !root.removed.list)
      return
    var cfg = root.removed.list
    helper.run(["trash", "--vault", root.config.vaultPath, "--list", JSON.stringify(cfg)], function (data) {
      toast.show(data.ok ? qsTr("%1 is in the trash of the vault.").arg(cfg.path) : String(data.message || qsTr("Could not delete it")), "", false)
    })
  }

  HelperCall { id: helper }

  Column {
    id: form

    width: parent.width
    spacing: Style.space(14)

    Row {
      width: parent.width
      spacing: Style.space(10)

      VaultCard {
        width: (parent.width - parent.spacing) / 2
        vaultPath: root.config.vaultPath
        fontFamily: root.fontFamily
        onVaultChosen: function (path) { root.settingChanged("vaultPath", path) }
      }

      SyncSummary {
        width: (parent.width - parent.spacing) / 2
        guide: root.syncGuide
        syncedAt: root.payload ? Model.clockText(root.payload.readAt) : ""
        fontFamily: root.fontFamily
        onGuideToggled: function (on) { root.settingChanged("obsidianSync", on) }
      }
    }

    Repeater {
      model: root.config.errors

      delegate: Text {
        required property string modelData

        width: form.width
        text: modelData
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Commons.Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)

      SettingsCaption { text: qsTr("YOUR LISTS · TABS IN THIS ORDER"); fontFamily: root.fontFamily }

      Text {
        width: parent.width
        text: qsTr("Notify: the items of the list count on the bar chip, and a new one from your phone pings it.")
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Util.alpha(Commons.Color.popups.text, 0.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(8)

      Repeater {
        model: root.config.lists

        delegate: ListRow {
          required property var modelData
          required property int index

          width: form.width
          cfg: modelData
          detail: Model.listDetail(modelData, root.payload)
          expanded: root.expandedId === modelData.id
          first: index === 0
          last: index === root.config.lists.length - 1
          vaultPath: root.config.vaultPath
          fontFamily: root.fontFamily
          onMoveUp: root.setLists(Model.moveList(root.config.lists, index, -1))
          onMoveDown: root.setLists(Model.moveList(root.config.lists, index, 1))
          onToggleExpand: root.expandedId = root.expandedId === modelData.id ? "" : modelData.id
          onChanged: function (field, value) { root.setLists(Model.updateList(root.config.lists, modelData.id, field, value)) }
          onRemoveRequested: root.remove(modelData)
        }
      }

      UndoToast {
        id: toast

        width: parent.width
        fontFamily: root.fontFamily
        onUndo: if (root.removed && root.removed.list) root.setLists(Model.insertList(root.config.lists, root.removed.list, root.removed.index))
        onAction: root.trashRemoved()
      }

      DashedButton {
        width: parent.width
        text: qsTr("+  Add a list")
        fontFamily: root.fontFamily
        onClicked: root.addListRequested()
      }
    }

    Rectangle { width: parent.width; height: 1; color: Util.alpha(Commons.Color.popups.text, 0.08) }

    ReminderSettings {
      visible: root.config.lists.some(function (l) { return l.type === "board" })
      width: parent.width
      config: root.config
      fontFamily: root.fontFamily
      onSettingChanged: function (name, value) { root.settingChanged(name, value) }
    }

    SettingsCaption { text: qsTr("PREVIEWS AND REFRESH"); fontFamily: root.fontFamily }

    Toggle {
      width: parent.width
      label: qsTr("Link previews")
      description: qsTr("A saved link without a picture or title: the page is read once for them. Only the site sees it.")
      checked: root.config.linkPreviews !== false
      fontFamily: root.fontFamily
      onClicked: root.settingChanged("linkPreviews", !checked)
    }

    Toggle {
      width: parent.width
      label: qsTr("Tweet previews")
      description: qsTr("Author picture and first photo of saved tweets. fxtwitter.com sees the tweet links, once each.")
      checked: root.config.tweetPreviews === true
      fontFamily: root.fontFamily
      onClicked: root.settingChanged("tweetPreviews", !checked)
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      SettingsCaption { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Read the vault every"); fontFamily: root.fontFamily }

      ButtonGroup {
        options: [{ value: "10", label: "10 s" }, { value: "30", label: "30 s" }, { value: "60", label: "1 min" }]
        value: String(root.config.refreshIntervalSec)
        fontFamily: root.fontFamily
        onChanged: function (value) { root.settingChanged("refreshIntervalSec", Number(value)) }
      }
    }

    SettingsCaption { text: qsTr("Sync check command (advanced, optional)"); fontFamily: root.fontFamily; visible: !root.config.obsidianSync }

    TextField {
      visible: !root.config.obsidianSync
      width: parent.width
      text: root.config.syncCheckCommand || ""
      placeholderText: qsTr("A command that exits 0 while your sync works")
      font.family: root.fontFamily
      onEditingFinished: if (text.trim() !== root.config.syncCheckCommand) root.settingChanged("syncCheckCommand", text.trim())
    }
  }
}
