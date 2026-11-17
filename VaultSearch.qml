// Search the vault's files, for step 1 of Add a list. Typing filters the
// paths the helper lists; picking one reports it, and the sheet decides the
// kind. A picked file whose kind the scan did not work out waits for a kind
// on step 1, named by pendingPath.
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property string vaultPath: ""
  property var suggestions: []
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

  function detail(path) {
    var type = Model.suggestionTypeForPath(root.suggestions, path)
    return type !== "" ? type : qsTr("file")
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
    visible: root.searching
    model: root.results

    delegate: PickerOption {
      required property string modelData

      width: parent.width
      label: modelData
      detail: root.detail(modelData)
      fontFamily: root.fontFamily
      onClicked: root.picked(modelData)
    }
  }

  Text {
    visible: root.pendingPath !== ""
    width: parent.width
    text: qsTr("Adding %1 — pick a kind").arg(root.pendingPath)
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Commons.Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
