import QtQuick
import Quickshell.Io
import qs.Commons
import "Model.js" as Model
import "Board.js" as Board

// Shelf data service. The helper owns every vault read and write; this item
// schedules it and exposes one stable model to the panel.
//
// The rule that shapes this file: a failed read never discards a good payload.
// The payload is replaced only when a read comes back ok, so an unmounted disk
// or a stuck helper leaves the last known lists on screen with the error in
// the header instead of an empty popup.
Item {
  id: root

  property var settings: ({})

  readonly property var config: Model.normalizeSettings(settings)
  readonly property bool configured: config.vaultPath !== ""

  property var payload: null
  property bool loading: false
  property string error: ""
  property var fresh: []
  // What arrived since the popup was last open, on any screen. The chip keeps
  // its dot and the rows keep their NEW tag until the popup has been closed.
  readonly property var unseen: seenState.unseen
  property bool syncHealthy: true
  property string syncMessage: ""
  property string notice: ""

  readonly property int badge: Model.badgeCount(payload, config.lists)
  readonly property int freshBadge: Model.freshInBadgeLists(fresh, config.lists)
  readonly property int unseenBadge: Model.freshInBadgeLists(unseen, config.lists)
  readonly property int lateCount: Board.lateCount(payload, config.lists, reminders.today)
  readonly property string tooltip: {
    if (!configured)
      return qsTr("Obsidian Shelf: choose a vault folder")
    if (!syncHealthy)
      return syncMessage
    if (error !== "")
      return error
    return Model.tooltipText(payload, config.lists)
  }

  property bool refreshQueued: false
  property var actionQueue: []

  function helperPath() {
    return Qt.resolvedUrl("bin/obsidian-shelf").toString().replace(/^file:\/\//, "")
  }

  function listConfig(listId) {
    var lists = config.lists
    for (var i = 0; i < lists.length; i++)
      if (lists[i].id === listId)
        return lists[i]
    return null
  }

  function refresh() {
    if (!configured) {
      payload = null
      return
    }
    if (readProcess.running) {
      refreshQueued = true
      return
    }
    loading = true
    readProcess.command = [helperPath(), "read", "--vault", config.vaultPath, "--lists", JSON.stringify(config.lists)]
    readProcess.running = true
    watchdog.restart()
    if (config.syncCheckCommand !== "" && !syncProcess.running) {
      syncProcess.command = ["sh", "-c", config.syncCheckCommand]
      syncProcess.running = true
    } else if (config.syncCheckCommand === "") {
      syncHealthy = true
    }
  }

  function parse(text) {
    try {
      return JSON.parse(String(text || ""))
    } catch (e) {
      return null
    }
  }

  function applyRead(text) {
    var data = parse(text)
    if (!data || !data.ok) {
      error = data && data.message ? data.message : qsTr("The helper returned no lists")
      return
    }
    var added = Model.freshKeys(payload, data)
    seenState.update(data)
    payload = data
    error = ""
    if (Model.previewsPending(data, config) && !enrichProcess.running) {
      enrichProcess.command = [helperPath(), "enrich", "--vault", config.vaultPath, "--lists", JSON.stringify(config.lists),
                               "--previews", Model.previewArgument(config)]
      enrichProcess.running = true
    }
    if (added.length > 0) {
      fresh = added
      freshTimer.restart()
    }
  }

  // Each action is one helper call. Its arguments name the vault and the
  // list; the item, the lane and any new text are vault text, so they go as
  // JSON through the environment and a pipe to stdin, never through the
  // arguments, which every local user can read in the process list.
  function act(action, listId, args) {
    var cfg = listConfig(listId)
    if (!cfg || !configured || ["add", "edit", "done", "remove", "move", "date", "lane", "clear"].indexOf(action) < 0)
      return
    var payload = {}
    ;["item", "text", "section", "lane", "date", "time", "title"].forEach(function (key) {
      if (args && args[key] !== undefined && args[key] !== null && args[key] !== "")
        payload[key] = String(args[key])
    })
    actionQueue = actionQueue.concat([{
      command: ["sh", "-c", "printf '%s' \"$SHELF_TEXT\" | \"$0\" \"$@\"", helperPath(), action, "--vault", config.vaultPath, "--list", JSON.stringify(cfg)],
      text: JSON.stringify(payload)
    }])
    runNextAction()
  }

  function runNextAction() {
    if (actionProcess.running || actionQueue.length === 0)
      return
    var call = actionQueue[0]
    actionQueue = actionQueue.slice(1)
    actionProcess.environment = { "SHELF_TEXT": call.text }
    actionProcess.command = call.command
    actionProcess.running = true
  }

  function applyAction(text) {
    var data = parse(text)
    if (data && data.ok === false)
      showNotice(data.error === "changed" ? qsTr("Changed elsewhere, reloaded") : String(data.message || qsTr("The action failed")))
    else if (!data)
      showNotice(qsTr("The action failed"))
  }

  function openUrl(url) {
    if (!url)
      return
    openProcess.command = ["xdg-open", String(url)]
    openProcess.running = true
  }

  function clearUnseen() {
    seenState.markSeen()
  }

  function showNotice(text) {
    notice = text
    noticeTimer.restart()
  }

  onConfigChanged: Qt.callLater(refresh)

  Reminders {
    id: reminders

    helper: root.helperPath()
    config: root.config
  }

  SeenState {
    id: seenState

    helper: root.helperPath()
    lists: root.config.lists
    payload: root.payload
  }

  Timer {
    interval: root.config.refreshIntervalSec * 1000
    repeat: true
    running: root.configured
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: watchdog

    interval: 5000
    repeat: false
    onTriggered: {
      if (readProcess.running) {
        readProcess.running = false
        root.error = qsTr("The helper did not answer")
      }
    }
  }

  Timer {
    id: freshTimer

    interval: 3400
    repeat: false
    onTriggered: root.fresh = []
  }

  Timer {
    id: noticeTimer

    interval: 3000
    repeat: false
    onTriggered: root.notice = ""
  }

  Process {
    id: readProcess

    running: false
    command: []
    stdout: StdioCollector {
      id: readOutput
    }
    onExited: function (exitCode) {
      watchdog.stop()
      root.loading = false
      root.applyRead(readOutput.text)
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: actionProcess

    running: false
    command: []
    stdout: StdioCollector {
      id: actionOutput
    }
    onExited: function (exitCode) {
      root.applyAction(actionOutput.text)
      root.refresh()
      Qt.callLater(root.runNextAction)
    }
  }

  // Previews come from the network, so they load after the lists: the
  // rows show at once and pick up their pictures on the read that follows.
  Process {
    id: enrichProcess

    running: false
    command: []
    onExited: function (exitCode) { root.refresh() }
  }

  Process {
    id: openProcess

    running: false
    command: []
    onExited: function (exitCode) {
      if (exitCode !== 0)
        root.showNotice(qsTr("Could not open the link"))
    }
  }

  Process {
    id: syncProcess

    running: false
    command: []
    onExited: function (exitCode) {
      root.syncHealthy = exitCode === 0
      root.syncMessage = exitCode === 0 ? "" : qsTr("Sync check failed (exit %1)").arg(exitCode)
    }
  }
}
