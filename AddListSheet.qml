import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Add a list: lists found in the vault (one click), or a kind, then where it
// lives and its name, then a done screen. A new folder or file is created.
Column {
  id: root

  property var config: ({ vaultPath: "", lists: [] })
  property string fontFamily: Style.font.family
  property string step: "kind"
  property string kind: ""
  property string name: ""
  property string path: ""
  property bool pathIsNew: false
  property var sections: []
  property bool notify: true
  property var suggestions: []
  property var lastAdded: null
  property string doneText: ""
  property string error: ""

  signal added(var list)
  signal openRequested(string listId)
  signal cancelled()

  readonly property var kinds: ({
    folder: { glyph: "", title: qsTr("Links to read or watch"), name: qsTr("Read later"), description: qsTr("Articles, videos, posts. A folder with one note per link, shared from the phone.") },
    checklist: { glyph: "", title: qsTr("A checklist"), name: qsTr("Checklist"), description: qsTr("Tasks, groceries, ideas. One file; a ticked line leaves it.") },
    board: { glyph: "\uf181", title: qsTr("A board"), name: qsTr("Board"), description: qsTr("Cards in lanes, with dates and reminders. The same file as the Kanban plugin on your phone.") },
    sections: { glyph: "", title: qsTr("Notes by section"), name: qsTr("Notes"), description: qsTr("One file with headings: a meeting agenda (To discuss / Decided), a list by status (This week / Later), a retrospective (Good / Bad).") }
  })
  readonly property var info: kind !== "" ? kinds[kind] : null

  spacing: Style.space(14)

  function start() {
    step = "kind"
    error = ""
    helper.run(["scan", "--vault", config.vaultPath], function (data) {
      root.suggestions = (data.suggestions || []).filter(function (s) {
        return !root.config.lists.some(function (l) { return l.path.replace(/\/+$/, "") === s.path })
      })
    })
  }

  function pickKind(k) {
    kind = k
    name = kinds[k].name
    path = ""
    pathIsNew = false
    sections = k === "sections" ? [qsTr("To discuss"), qsTr("Decided")] : k === "board" ? [qsTr("To do"), qsTr("In progress"), qsTr("Done")] : []
    notify = k !== "sections"
    error = ""
    step = "details"
  }

  function addSuggestion(s) {
    kind = s.type
    finish({ type: s.type, path: s.path, name: s.path.split("/").pop().replace(/\.md$/i, "") }, s.type !== "sections")
  }

  function submit() {
    if (path === "") {
      error = qsTr("Choose where the list lives, or type a new name.")
      return
    }
    finish({ type: kind, path: path, name: name.trim() !== "" ? name.trim() : info.name }, notify)
  }

  function finish(spec, badge) {
    var list = { id: Model.newListId(config.lists, spec.name), name: spec.name.slice(0, 24), type: spec.type, path: spec.path, badge: badge, onDone: "delete" }
    var args = ["create", "--vault", config.vaultPath, "--list", JSON.stringify(list)]
    var input = JSON.stringify({ sections: spec.type === "sections" || spec.type === "board" ? sections : [] })
    helper.run(args, function (data) {
      if (!data.ok) {
        root.error = String(data.message || qsTr("Could not create it"))
        return
      }
      root.lastAdded = list
      root.doneText = data.created
        ? qsTr("%1 was created in your vault. It syncs to your phone like any note.").arg(list.path)
        : qsTr("It reads %1. Nothing in it changed.").arg(list.path)
      root.added(list)
      root.step = "done"
    }, input)
  }

  Component.onCompleted: start()

  HelperCall { id: helper }

  Row {
    spacing: Style.space(8)

    RowButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: ""
      label: qsTr("Back")
      fontFamily: root.fontFamily
      onClicked: {
        if (root.step === "details")
          root.step = "kind"
        else
          root.cancelled()
      }
    }

    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("ADD A LIST"); textFormat: Text.PlainText; color: Color.popups.text; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; font.letterSpacing: Style.space(2) }
  }

  // ---- Step 1: found in the vault, or a kind
  Column {
    visible: root.step === "kind"
    width: parent.width
    spacing: Style.space(10)

    SettingsCaption { text: qsTr("FOUND IN YOUR VAULT · ONE CLICK"); fontFamily: root.fontFamily }

    Text {
      visible: root.suggestions.length === 0
      width: parent.width
      text: qsTr("Nothing new: every list found in the vault is already on the shelf.")
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Util.alpha(Color.popups.text, 0.65)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      model: root.suggestions.slice(0, 4)

      delegate: PickerOption {
        required property var modelData

        width: parent.width
        label: "+ " + modelData.path
        detail: (modelData.type === "folder" ? qsTr("links") : modelData.type === "checklist" ? qsTr("checklist") : modelData.type === "board" ? qsTr("board") : qsTr("sections")) + " · " + modelData.count
        fontFamily: root.fontFamily
        onClicked: root.addSuggestion(modelData)
      }
    }

    SettingsCaption { text: qsTr("OR START A NEW ONE"); fontFamily: root.fontFamily }

    Repeater {
      model: ["folder", "checklist", "board", "sections"]

      delegate: KindCard {
        required property string modelData

        width: parent.width
        glyph: root.kinds[modelData].glyph
        title: root.kinds[modelData].title
        description: root.kinds[modelData].description
        fontFamily: root.fontFamily
        onClicked: root.pickKind(modelData)
      }
    }
  }

  // ---- Step 2: details
  Column {
    visible: root.step === "details"
    width: parent.width
    spacing: Style.space(12)

    SettingsCaption { text: root.info ? root.info.title.toUpperCase() : ""; fontFamily: root.fontFamily }

    TextField {
      width: parent.width
      text: root.name
      placeholderText: qsTr("Name in the tab")
      font.family: root.fontFamily
      onTextChanged: root.name = text
    }

    SettingsCaption { text: root.kind === "folder" ? qsTr("Folder in the vault") : qsTr("File in the vault"); fontFamily: root.fontFamily }

    Text {
      visible: root.path !== ""
      width: parent.width
      text: root.path + (root.pathIsNew ? qsTr("  (new, created when you add)") : "")
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Loader {
      width: parent.width
      active: root.step === "details" && root.kind !== ""
      sourceComponent: VaultPicker {
        vaultPath: root.config.vaultPath
        kind: root.kind === "folder" ? "folder" : "file"
        current: root.path
        suggestedName: root.name
        fontFamily: root.fontFamily
        onPicked: function (path, isNew) { root.path = path; root.pathIsNew = isNew; root.error = "" }
      }
    }

    SectionChips {
      visible: root.kind === "sections" || root.kind === "board"
      width: parent.width
      sections: root.sections
      fontFamily: root.fontFamily
      onEdited: function (sections) { root.sections = sections }
    }

    Toggle {
      width: parent.width
      label: qsTr("Notify on new items")
      description: qsTr("Its items count on the bar chip, and a new one pings it.")
      checked: root.notify
      fontFamily: root.fontFamily
      onClicked: root.notify = !root.notify
    }

    Text {
      visible: root.error !== ""
      width: parent.width
      text: root.error
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Row {
      spacing: Style.space(8)

      Button { text: qsTr("Cancel"); onClicked: root.step = "kind" }
      Button { text: qsTr("Add to shelf"); bordered: true; background: Color.accent; foreground: Color.popups.background; onClicked: root.submit() }
    }
  }

  // ---- Step 3: done
  Column {
    visible: root.step === "done"
    width: parent.width
    spacing: Style.space(12)

    Text { text: ""; textFormat: Text.PlainText; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.displayLarge }
    Text { width: parent.width; text: qsTr("%1 is on the shelf").arg(root.lastAdded ? root.lastAdded.name : ""); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.popups.text; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
    Text { width: parent.width; text: root.doneText; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Util.alpha(Color.popups.text, 0.7); font.family: root.fontFamily; font.pixelSize: Style.font.body }

    Row {
      spacing: Style.space(8)

      Button { text: qsTr("Add another"); onClicked: root.start() }
      Button { text: qsTr("Open the tab"); bordered: true; background: Color.accent; foreground: Color.popups.background; onClicked: root.openRequested(root.lastAdded.id) }
    }
  }
}
