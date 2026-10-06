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

  onOpenedChanged: if (opened) shelf.refresh()

  Service {
    id: shelf

    settings: root.settings
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
      return JSON.stringify({ configured: shelf.configured, loading: shelf.loading, error: shelf.error, syncHealthy: shelf.syncHealthy, badge: shelf.badge, readAt: shelf.payload ? shelf.payload.readAt : "" })
    }
  }

  ShelfChip {
    id: chip

    anchors.fill: parent
    bar: root.bar
    count: shelf.badge
    pinging: shelf.freshBadge > 0
    urgent: !shelf.syncHealthy
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(placeholder.implicitHeight, Style.space(716))

    Text {
      id: placeholder

      width: parent.width
      text: qsTr("%1 open").arg(shelf.badge)
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
}
