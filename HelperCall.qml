import QtQuick
import Quickshell.Io

// One-off helper calls for the settings: run(args, done) queues a call and
// hands its JSON answer to done. Calls run one at a time, in order.
Item {
  id: root

  property var queue: []
  property var current: null

  function helperPath() {
    return Qt.resolvedUrl("bin/obsidian-shelf").toString().replace(/^file:\/\//, "")
  }

  // Vault text for the helper goes in `input`, never in `args`: it reaches
  // stdin through the environment and a pipe, out of the process list.
  function run(args, done, input) {
    queue = queue.concat([{ args: args, done: done, input: input === undefined ? null : String(input) }])
    next()
  }

  function next() {
    if (process.running || queue.length === 0)
      return
    current = queue[0]
    queue = queue.slice(1)
    if (current.input !== null) {
      process.environment = { "SHELF_TEXT": current.input }
      process.command = ["sh", "-c", "printf '%s' \"$SHELF_TEXT\" | \"$0\" \"$@\"", helperPath()].concat(current.args)
    } else {
      process.environment = {}
      process.command = [helperPath()].concat(current.args)
    }
    process.running = true
  }

  Process {
    id: process

    running: false
    command: []
    stdout: StdioCollector { id: output }
    onExited: function (exitCode) {
      var data
      try {
        data = JSON.parse(String(output.text || ""))
      } catch (e) {
        data = { ok: false, error: "io", message: qsTr("The helper gave no answer") }
      }
      var call = root.current
      root.current = null
      if (call && call.done)
        call.done(data)
      Qt.callLater(root.next)
    }
  }
}
