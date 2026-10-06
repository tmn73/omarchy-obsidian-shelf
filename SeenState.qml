import QtQuick
import Quickshell.Io
import "Model.js" as Model

// What the user has seen, shared by every screen. Each bar runs its own
// widget, so the state lives in one file that the helper writes and every bar
// watches: closing the popup on one screen clears the chip on all of them.
Item {
  id: root

  property string helper: ""
  property var lists: []
  property var payload: null
  // {listId: {path, keys}}, as the helper stores it.
  property var state: null
  property string filePath: ""

  readonly property var unseen: Model.unseenKeys(payload, state)

  // Called with each good read, before the payload changes, so rows created
  // for new items already know they are new.
  function update(data) {
    state = data.seen || null
    if (data.seenPath)
      filePath = data.seenPath
  }

  function markSeen() {
    if (!payload)
      return
    var keys = Model.seenFromPayload(payload)
    // Here first, so this chip clears at once; the file tells the other bars.
    var next = {}
    for (var id in state || {})
      next[id] = state[id]
    for (var listId in keys)
      next[listId] = { path: next[listId] ? next[listId].path : "", keys: keys[listId] }
    state = next
    writer.environment = { "SHELF_TEXT": JSON.stringify(keys) }
    writer.command = ["sh", "-c", "printf '%s' \"$SHELF_TEXT\" | \"$0\" \"$@\"", helper, "seen", "--lists", JSON.stringify(lists)]
    writer.running = true
  }

  function applyFile(text) {
    try {
      var data = JSON.parse(String(text || ""))
      if (data && typeof data === "object")
        state = data
    } catch (e) {
      // A half-written file is replaced on the next write; keep the last state.
    }
  }

  FileView {
    path: root.filePath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.applyFile(text())
  }

  Process {
    id: writer

    running: false
    command: []
  }
}
