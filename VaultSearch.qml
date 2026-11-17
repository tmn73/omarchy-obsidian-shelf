// Search the vault's files, for step 1 of Add a list. Typing filters the
// paths the helper lists; picking one reports it, and the sheet decides the
// kind. A picked file whose kind the scan did not work out waits for a kind
// on step 1, named by pendingPath. A file a list already reads shows as "on
// the shelf" and cannot be picked.
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property string vaultPath: ""
  property var suggestions: []
  property var lists: []
  property string pendingPath: ""
  property string fontFamily: Style.font.family
  property string query: ""
  property var paths: []

  readonly property bool searching: query.trim() !== ""
  readonly property var results: Model.searchVaultPaths(root.paths, root.query)

  signal picked(string path)

  function load() {
    if (vaultPath !== "")
      helper.run(["paths", "--vault", vaultPath, "--kind", "file"], function (data) { root.paths = data.paths || [] })
  }

  function clear() { root.query = "" }

  // The words the sheet shows for a list type, here and on the found lists.
  function kindLabel(type) {
    return type === "folder" ? qsTr("links") : type === "checklist" ? qsTr("checklist") : type === "board" ? qsTr("board") : type === "sections" ? qsTr("sections") : qsTr("file")
  }

  function detail(path) {
    if (Model.pathOnShelf(root.lists, path))
      return qsTr("on the shelf")
    return kindLabel(Model.suggestionTypeForPath(root.suggestions, path))
  }

  Component.onCompleted: load()

  HelperCall { id: helper }

  spacing: Style.space(10)

  TextField {
    width: parent.width
    text: root.query
    placeholderText: qsTr("Search the vault…")
    font.family: root.fontFamily
    onTextChanged: root.query = text
  }

  SettingsCaption { visible: root.searching; text: qsTr("SEARCH RESULTS"); fontFamily: root.fontFamily }

  Text {
    visible: root.searching && root.results.length === 0
    width: parent.width
    text: qsTr("Nothing matches")
    textFormat: Text.PlainText
    color: Util.alpha(Commons.Color.popups.text, 0.65)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: root.results

    delegate: PickerOption {
      required property string modelData

      width: parent.width
      enabled: !Model.pathOnShelf(root.lists, modelData)
      opacity: enabled ? 1 : 0.45
      label: modelData
      detail: root.detail(modelData)
      fontFamily: root.fontFamily
      onClicked: root.picked(modelData)
    }
  }

  Text {
    visible: root.pendingPath !== ""
    width: parent.width
    text: qsTr("Adding %1: pick a checklist, a board or notes by section").arg(root.pendingPath)
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Commons.Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
