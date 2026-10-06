import QtQuick
import qs.Commons
import "Model.js" as Model

// Popup layout: header, tabs, the active list, then the key hints.
//
// The active list is loaded by type. Every list component answers the same
// small contract (service, listConfig, listPayload, contentHeightHint,
// moveHighlight, activateCurrent, doneCurrent), so this file never needs to
// know what a row looks like.
Item {
  id: root

  property var service: null
  property var syncGuide: null
  property int activeIndex: 0
  property int openCount: 0
  property bool settingsOpen: false
  property bool adding: false
  property Item addBar: addBarItem
  property string fontFamily: Style.font.family

  signal settingsToggled()
  signal settingChanged(string name, var value)

  readonly property bool inputFocused: addBarItem.inputFocused || settingsView.inputFocused || (listLoader.item ? listLoader.item.editing === true || listLoader.item.typing === true : false)

  readonly property var lists: service ? service.config.lists : []
  readonly property bool configured: service ? service.configured : false
  readonly property var activeConfig: lists.length > 0 ? lists[Math.min(activeIndex, lists.length - 1)] : null
  readonly property var activePayload: activeConfig && service ? Model.findList(service.payload, activeConfig.id) : null
  // The room the panel gives, set by Panel.qml. The list takes what the
  // header, tabs, add bar and key hints leave, so nothing gets cut.
  property real availableHeight: Style.space(716)
  readonly property real chromeHeight: header.implicitHeight + (noticeText.visible ? noticeText.implicitHeight : 0)
    + (syncCard.visible ? syncCard.implicitHeight : 0) + (tabBar.visible ? tabBar.implicitHeight : 0)
    + (addBarItem.visible ? addBarItem.implicitHeight : 0) + 1 + (hints.visible ? hints.implicitHeight : 0) + content.spacing * 7
  readonly property real maxListHeight: Math.max(Style.space(120), Math.min(Style.space(470), availableHeight - chromeHeight))
  readonly property var listSources: ({ folder: "FolderList.qml", checklist: "ChecklistList.qml", sections: "SectionsList.qml", board: "BoardList.qml" })
  readonly property bool canAdd: activeConfig !== null && activeConfig.type !== "folder" && !settingsOpen && !adding
  readonly property var sectionNames: Model.addTargets(activeConfig, activePayload)

  implicitWidth: Style.space(440)
  implicitHeight: content.implicitHeight

  function tabModel() {
    var payload = service ? service.payload : null
    return lists.map(function (cfg) {
      return { name: cfg.name, count: Model.listItemCount(Model.findList(payload, cfg.id)) }
    })
  }

  function syncText() {
    if (!service)
      return ""
    if (!service.configured)
      return qsTr("choose a vault folder")
    if (service.error !== "")
      return service.error
    if (!service.payload)
      return qsTr("reading the vault")
    var vault = service.config.vaultPath.replace(/\/+$/, "").split("/").pop()
    var line = qsTr("synced %1 · %2").arg(Model.clockText(service.payload.readAt)).arg(vault)
    return syncGuide && syncGuide.running ? qsTr("Obsidian Sync on · ") + line : line
  }

  function nextTab(direction) {
    if (lists.length === 0)
      return
    activeIndex = (activeIndex + direction + lists.length) % lists.length
  }

  // A key action for the active list (moveHighlight, doneCurrent, moveCard...).
  function forward(name, arg) {
    if (listLoader.item && listLoader.item[name])
      listLoader.item[name](arg)
  }

  function focusAdd() {
    if (root.addBar && root.addBar.visible)
      root.addBar.focusInput()
  }

  // A list whose folder or file went missing: make it again, empty. A notes
  // file comes back without headings, and its tab says how to add them.
  function createActiveList() {
    if (!activeConfig || !service)
      return
    var args = ["create", "--vault", service.config.vaultPath, "--list", JSON.stringify(activeConfig)]
    creator.run(args, function () { root.service.refresh() })
  }

  function openList(listId) {
    adding = false
    if (settingsOpen)
      settingsToggled()
    Qt.callLater(function () {
      for (var i = 0; i < root.lists.length; i++)
        if (root.lists[i].id === listId)
          root.activeIndex = i
    })
  }

  function playOpen() {
    adding = false
    openCount++
    dropIn.restart()
  }

  HelperCall { id: creator }

  Column {
    id: content

    width: root.width
    spacing: Style.space(14)
    transform: Translate { id: dropShift }

    PopupHeader {
      id: header

      width: parent.width
      syncText: root.syncText()
      failing: root.service ? root.service.error !== "" : false
      settingsOpen: root.settingsOpen
      fontFamily: root.fontFamily
      onSettingsToggled: root.settingsToggled()
    }

    Text {
      id: noticeText

      width: parent.width
      visible: root.service && root.service.notice !== ""
      text: root.service ? root.service.notice : ""
      textFormat: Text.PlainText
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
    }

    Flickable {
      width: parent.width
      visible: root.adding
      height: Math.min(addSheet.implicitHeight, Style.space(600))
      contentHeight: addSheet.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Loader {
        id: addSheet

        width: parent.width
        active: root.adding
        sourceComponent: AddListSheet {
          config: root.service ? root.service.config : ({ vaultPath: "", lists: [] })
          fontFamily: root.fontFamily
          onAdded: function (list) { root.settingChanged("lists", root.service.config.lists.concat([list])) }
          onCancelled: root.adding = false
          onOpenRequested: function (listId) { root.openList(listId) }
        }
      }
    }

    Flickable {
      width: parent.width
      visible: root.settingsOpen && !root.adding
      height: Math.min(settingsView.implicitHeight, Style.space(560))
      contentHeight: settingsView.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      SettingsView {
        id: settingsView

        width: parent.width
        config: root.service ? root.service.config : ({ vaultPath: "", refreshIntervalSec: 10, syncCheckCommand: "", lists: [], errors: [] })
        payload: root.service ? root.service.payload : null
        syncGuide: root.syncGuide
        fontFamily: root.fontFamily
        onSettingChanged: function (name, value) { root.settingChanged(name, value) }
        onAddListRequested: root.adding = true
      }
    }

    SyncCard {
      id: syncCard

      width: parent.width
      visible: !root.settingsOpen && root.syncGuide !== null && root.syncGuide.needsAction
      guide: root.syncGuide
      fontFamily: root.fontFamily
      onHideRequested: root.settingChanged("obsidianSync", false)
    }

    EmptyShelf {
      width: parent.width
      visible: !root.settingsOpen && !root.adding && (!root.configured || root.lists.length === 0)
      configured: root.configured
      fontFamily: root.fontFamily
      onVaultChosen: function (path) { root.settingChanged("vaultPath", path) }
      onAddRequested: root.adding = true
    }

    TabBar {
      id: tabBar

      width: parent.width
      visible: !root.settingsOpen && !root.adding && root.lists.length > 0
      tabs: root.tabModel()
      currentIndex: root.activeIndex
      fontFamily: root.fontFamily
      onActivated: function (index) { root.activeIndex = index }
    }

    Item {
      id: listArea

      width: parent.width
      visible: !root.settingsOpen && !root.adding && root.configured && root.lists.length > 0
      height: Math.min(listLoader.item ? listLoader.item.contentHeightHint : Style.space(120), root.maxListHeight)

      Loader {
        id: listLoader

        anchors.fill: parent
        source: root.activeConfig ? root.listSources[root.activeConfig.type] : ""
        onLoaded: {
          item.service = Qt.binding(function () { return root.service })
          item.listConfig = Qt.binding(function () { return root.activeConfig })
          item.listPayload = Qt.binding(function () { return root.activePayload })
          item.fontFamily = Qt.binding(function () { return root.fontFamily })
          item.openCount = Qt.binding(function () { return root.openCount })
          item.settingsRequested.connect(root.settingsToggled)
          item.createRequested.connect(root.createActiveList)
        }
      }

      Text {
        anchors.centerIn: parent
        visible: listLoader.status === Loader.Error
        text: qsTr("This list type cannot be shown yet")
        textFormat: Text.PlainText
        color: Util.alpha(Color.popups.text, 0.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    AddBar {
      id: addBarItem

      width: parent.width
      visible: root.canAdd
      sections: root.sectionNames
      placeholder: root.activeConfig && root.activeConfig.type === "board" ? qsTr("New card") : root.sectionNames.length > 0 ? qsTr("New %1 topic").arg(section.toLowerCase()) : qsTr("New todo")
      fontFamily: root.fontFamily
      onSubmitted: function (text, section) {
        if (root.service && root.activeConfig)
          root.service.act("add", root.activeConfig.id, { text: text, section: root.sectionNames.length > 0 ? section : "" })
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.popups.text, 0.08)
    }

    KeyHints {
      id: hints

      visible: !root.settingsOpen
      fontFamily: root.fontFamily
    }
  }

  ParallelAnimation {
    id: dropIn

    NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: Style.duration(450); easing.type: Easing.OutCubic }
    NumberAnimation { target: dropShift; property: "y"; from: -Style.space(10); to: 0; duration: Style.duration(450); easing.type: Easing.OutCubic }
    NumberAnimation { target: content; property: "scale"; from: 0.98; to: 1; duration: Style.duration(450); easing.type: Easing.OutCubic }
  }
}
