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
  property Item addBar: addBarItem
  property string fontFamily: Style.font.family

  signal settingsToggled()
  signal settingChanged(string name, var value)

  readonly property bool inputFocused: addBarItem.inputFocused || settingsView.inputFocused || (listLoader.item ? listLoader.item.editing === true : false)

  readonly property var lists: service ? service.config.lists : []
  readonly property var activeConfig: lists.length > 0 ? lists[Math.min(activeIndex, lists.length - 1)] : null
  readonly property var activePayload: activeConfig && service ? Model.findList(service.payload, activeConfig.id) : null
  readonly property real maxListHeight: Style.space(470)
  readonly property var listSources: ({ folder: "FolderList.qml", checklist: "ChecklistList.qml", sections: "SectionsList.qml" })
  readonly property bool canAdd: activeConfig !== null && activeConfig.type !== "folder" && !settingsOpen
  readonly property var sectionNames: {
    if (!activeConfig || activeConfig.type !== "sections" || !activePayload)
      return []
    return (Model.toArray(activePayload.sections) || []).map(function (s) { return s.heading })
  }

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

  function moveHighlight(dy) {
    if (listLoader.item && listLoader.item.moveHighlight)
      listLoader.item.moveHighlight(dy)
  }

  function activateCurrent() {
    if (listLoader.item && listLoader.item.activateCurrent)
      listLoader.item.activateCurrent()
  }

  function doneCurrent() {
    if (listLoader.item && listLoader.item.doneCurrent)
      listLoader.item.doneCurrent()
  }

  function editCurrent() {
    if (listLoader.item && listLoader.item.editCurrent)
      listLoader.item.editCurrent()
  }

  function removeCurrent() {
    if (listLoader.item && listLoader.item.removeCurrent)
      listLoader.item.removeCurrent()
  }

  function focusAdd() {
    if (root.addBar && root.addBar.visible)
      root.addBar.focusInput()
  }

  function playOpen() {
    openCount++
    dropIn.restart()
  }

  Column {
    id: content

    width: root.width
    spacing: Style.space(14)
    transform: Translate { id: dropShift }

    PopupHeader {
      width: parent.width
      syncText: root.syncText()
      failing: root.service ? root.service.error !== "" : false
      settingsOpen: root.settingsOpen
      fontFamily: root.fontFamily
      onSettingsToggled: root.settingsToggled()
    }

    Text {
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
      visible: root.settingsOpen
      height: Math.min(settingsView.implicitHeight, Style.space(560))
      contentHeight: settingsView.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      SettingsView {
        id: settingsView

        width: parent.width
        config: root.service ? root.service.config : ({ vaultPath: "", refreshIntervalSec: 10, syncCheckCommand: "", lists: [], errors: [] })
        fontFamily: root.fontFamily
        onSettingChanged: function (name, value) { root.settingChanged(name, value) }
      }
    }

    SyncCard {
      width: parent.width
      visible: !root.settingsOpen && root.syncGuide !== null && root.syncGuide.needsAction
      guide: root.syncGuide
      fontFamily: root.fontFamily
      onHideRequested: root.settingChanged("obsidianSync", false)
    }

    TabBar {
      width: parent.width
      visible: !root.settingsOpen && root.lists.length > 0
      tabs: root.tabModel()
      currentIndex: root.activeIndex
      fontFamily: root.fontFamily
      onActivated: function (index) { root.activeIndex = index }
    }

    Item {
      id: listArea

      width: parent.width
      visible: !root.settingsOpen
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
      placeholder: root.sectionNames.length > 0 ? qsTr("New %1 topic").arg(section.toLowerCase()) : qsTr("New todo")
      fontFamily: root.fontFamily
      onSubmitted: function (text, section) {
        if (root.service && root.activeConfig)
          root.service.act("add", root.activeConfig.id, { text: text, section: root.activeConfig.type === "sections" ? section : "" })
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(Color.popups.text, 0.08)
    }

    KeyHints {
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
