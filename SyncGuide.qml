import QtQuick
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Guides the Obsidian Sync setup on this machine, one step at a time.
//
// The helper reports the next step. Steps that need the user (install, log
// in, pick a remote vault) run in a terminal they can see, so a password
// never passes through the plugin. While a step is pending and the popup is
// open, the state is read again every few seconds, so the card moves on by
// itself when the terminal is done.
Item {
  id: root

  property string vaultPath: ""
  property bool active: true
  property bool watching: false

  property string syncState: ""
  property string client: ""
  property string message: ""

  readonly property var step: active ? Model.syncStep(syncState) : null
  readonly property bool needsAction: step !== null
  readonly property bool running: syncState === "running"

  function helperPath() {
    return Qt.resolvedUrl("bin/obsidian-shelf").toString().replace(/^file:\/\//, "")
  }

  function scriptPath(name) {
    return Qt.resolvedUrl("bin/" + name).toString().replace(/^file:\/\//, "")
  }

  function quote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function refresh() {
    if (!active || vaultPath === "" || stateProcess.running)
      return
    stateProcess.command = [helperPath(), "sync-state", "--vault", vaultPath]
    stateProcess.running = true
  }

  function openTerminal(script) {
    terminalProcess.command = ["omarchy-launch-floating-terminal-with-presentation", script]
    terminalProcess.running = true
  }

  function runSyncStep() {
    message = ""
    var ob = quote(client)
    if (syncState === "no-client")
      openTerminal("bun add -g obsidian-headless || npm install -g obsidian-headless")
    else if (syncState === "logged-out")
      openTerminal(quote(scriptPath("obsidian-shelf-login")) + " " + ob)
    else if (syncState === "unlinked")
      openTerminal(quote(scriptPath("obsidian-shelf-link")) + " " + ob + " " + quote(vaultPath))
    else if (syncState === "stopped" && !serviceProcess.running) {
      serviceProcess.command = [helperPath(), "sync-service", "--vault", vaultPath]
      serviceProcess.running = true
    }
  }

  onVaultPathChanged: Qt.callLater(refresh)
  onActiveChanged: Qt.callLater(refresh)
  onWatchingChanged: if (watching) refresh()

  Timer {
    interval: 3000
    repeat: true
    running: root.active && root.watching && root.needsAction
    onTriggered: root.refresh()
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProcess

    running: false
    command: []
    stdout: StdioCollector { id: stateOutput }
    onExited: function (exitCode) {
      try {
        var data = JSON.parse(String(stateOutput.text || ""))
        root.syncState = String(data.state || "")
        root.client = String(data.client || "")
      } catch (e) {
        root.message = qsTr("Could not read the sync state")
      }
    }
  }

  Process {
    id: terminalProcess

    running: false
    command: []
  }

  Process {
    id: serviceProcess

    running: false
    command: []
    stdout: StdioCollector { id: serviceOutput }
    onExited: function (exitCode) {
      try {
        var data = JSON.parse(String(serviceOutput.text || ""))
        if (!data.ok)
          root.message = String(data.message || qsTr("Could not start the sync service"))
      } catch (e) {
        root.message = qsTr("Could not start the sync service")
      }
      root.refresh()
    }
  }
}
