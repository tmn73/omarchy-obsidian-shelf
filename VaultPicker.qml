import QtQuick
import qs.Commons
import qs.Ui

// Choose a folder or a file of the vault, or a new one. Typing filters the
// existing paths and proposes the typed name as a new path.
Column {
  id: root

  property string vaultPath: ""
  property string kind: "file"          // "folder" or "file"
  property string current: ""
  property string suggestedName: ""
  property string fontFamily: Style.font.family
  property var paths: []

  signal picked(string path, bool isNew)

  readonly property string query: field.text.trim()
  readonly property string newPath: {
    var name = query !== "" ? query : suggestedName
    if (name === "")
      return ""
    return kind === "file" && !/\.md$/i.test(name) ? name + ".md" : name.replace(/\/+$/, "")
  }
  readonly property var matches: paths.filter(function (p) {
    return query === "" || p.toLowerCase().indexOf(query.toLowerCase()) >= 0
  }).slice(0, 8)
  readonly property bool offerNew: newPath !== "" && paths.indexOf(newPath) < 0

  spacing: Style.space(6)

  function load() {
    if (vaultPath !== "")
      helper.run(["paths", "--vault", vaultPath, "--kind", kind], function (data) { root.paths = data.paths || [] })
  }

  Component.onCompleted: load()
  onKindChanged: load()

  HelperCall { id: helper }

  TextField {
    id: field

    width: parent.width
    placeholderText: root.kind === "folder" ? qsTr("Search folders, or type a new name") : qsTr("Search files, or type a new name")
    font.family: root.fontFamily
    onAccepted: if (root.offerNew) root.picked(root.newPath, true)
    Component.onCompleted: forceActiveFocus()
  }

  Rectangle {
    width: parent.width
    height: options.implicitHeight + Style.space(8)
    radius: Style.space(9)
    color: Util.alpha(Color.popups.text, 0.04)
    border.width: 1
    border.color: Util.alpha(Color.popups.text, 0.08)

    Column {
      id: options

      x: Style.space(4)
      y: Style.space(4)
      width: parent.width - Style.space(8)

      PickerOption {
        visible: root.offerNew
        label: (root.kind === "folder" ? qsTr("+ New folder ") : qsTr("+ New file ")) + "\"" + root.newPath + "\""
        detail: qsTr("created for you")
        fontFamily: root.fontFamily
        onClicked: root.picked(root.newPath, true)
      }

      Repeater {
        model: root.matches

        delegate: PickerOption {
          required property string modelData

          label: modelData
          detail: modelData === root.current ? qsTr("current") : ""
          selected: modelData === root.current
          fontFamily: root.fontFamily
          onClicked: root.picked(modelData, false)
        }
      }

      Text {
        visible: !root.offerNew && root.matches.length === 0
        padding: Style.space(10)
        text: qsTr("Nothing matches")
        textFormat: Text.PlainText
        color: Util.alpha(Color.popups.text, 0.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
