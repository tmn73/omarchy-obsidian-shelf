import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar entry point for Obsidian Shelf.
//
// This file owns the chip, the popup frame and the IPC surface. Rows belong to
// their list components, payload meaning belongs to Model.js, and scheduling
// belongs to Service.qml.
Panel {
  id: root

  moduleName: "tmn73.obsidian"
  ipcTarget: "tmn73.obsidian"
  manageIpc: false

  implicitWidth: chip.implicitWidth
  implicitHeight: chip.implicitHeight

  // The only place in the plugin that persists anything.
  function setSetting(name, value) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) {
      if (key !== "id")
        entry[key] = root.settings[key]
    }
    entry[name] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  property bool showSettings: false
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  onOpenedChanged: {
    if (!opened) {
      shelf.clearUnseen()
      return
    }
    shelf.refresh()
    showSettings = false
    popup.playOpen()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: shelf

    settings: root.settings
  }

  SyncGuide {
    id: syncGuide

    vaultPath: shelf.config.vaultPath
    active: shelf.config.obsidianSync
    watching: root.opened
    onRunningChanged: if (running) shelf.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { shelf.refresh(); return "ok" }
    function badge(): string { return String(shelf.badge) }
    // What the service holds, for scripts and for debugging a silent chip.
    function status(): string {
      return JSON.stringify({ configured: shelf.configured, loading: shelf.loading, error: shelf.error, syncHealthy: shelf.syncHealthy, badge: shelf.badge, unseen: shelf.unseenBadge, readAt: shelf.payload ? shelf.payload.readAt : "" })
    }
  }

  ShelfChip {
    id: chip

    anchors.fill: parent
    bar: root.bar
    count: shelf.badge
    pinging: shelf.freshBadge > 0
    marked: shelf.unseenBadge > 0 && !root.opened
    late: shelf.lateCount > 0
    urgent: syncGuide.active ? syncGuide.syncState === "stopped" : !shelf.syncHealthy
    tooltipText: shelf.tooltip
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton)
        shelf.refresh()
      else
        root.toggle()
    }
  }

  KeyboardPanel {
    id: panel

    anchorItem: chip
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(popup.implicitHeight, Style.space(716))

    PanelKeyCatcher {
      id: keyCatcher

      anchors.fill: parent
      blocked: popup.inputFocused
      onMoveRequested: function (dx, dy) { if (dy !== 0) popup.forward("moveHighlight", dy); else if (dx !== 0) popup.forward("moveCard", dx) }
      onActivateRequested: popup.forward("activateCurrent")
      onDeleteRequested: popup.forward("removeCurrent")
      onCloseRequested: root.close()
      onTabRequested: function (direction) { popup.nextTab(direction) }
      onTextKey: function (character) {
        var key = String(character || "").toLowerCase()
        if (key === "d")
          popup.forward("doneCurrent")
        else if (key === "e")
          Qt.callLater(popup.forward, "editCurrent")
        else if (key === "x")
          popup.forward("removeCurrent")
        else if (key === "a")
          Qt.callLater(popup.focusAdd)
        else if (key === "r")
          shelf.refresh()
        else if (key === "t")
          Qt.callLater(popup.forward, "dateCurrent")
        else if (key === "s")
          Qt.callLater(popup.forward, "statusCurrent")
      }

      ShelfPopup {
        id: popup

        anchors.fill: parent
        service: shelf
        syncGuide: syncGuide
        settingsOpen: root.showSettings
        availableHeight: panel.fittedContentHeight(100000, Style.space(716)) - panel.verticalContentInset
        fontFamily: root.fontFamily
        onSettingsToggled: root.showSettings = !root.showSettings
        onSettingChanged: function (name, value) { root.setSetting(name, value) }
      }
    }
  }
}
