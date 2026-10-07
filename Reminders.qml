import QtQuick
import Quickshell.Io
import "Board.js" as Board
import "Model.js" as Model

// Asks the helper for board reminders every minute, and keeps today's date
// for the late count. Each bar runs one; the helper's lock makes one
// notification of it.
Item {
  id: root

  property string helper: ""
  property var config: ({ vaultPath: "", lists: [], reminderTime: "09:00" })
  property string today: Board.isoDay(new Date())

  readonly property bool wanted: config.vaultPath !== "" && (config.lists || []).some(function (l) { return l.type === "board" && l.remind !== false })

  function run() {
    today = Board.isoDay(new Date())
    if (!wanted || process.running)
      return
    process.command = [helper, "remind", "--vault", config.vaultPath, "--lists", JSON.stringify(config.lists),
                       "--summary-time", config.reminderTime, "--sound", Model.soundArgument(config)]
    process.running = true
  }

  Timer {
    interval: 60000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.run()
  }

  Process {
    id: process

    running: false
    command: []
  }
}
