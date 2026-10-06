import QtQuick
import qs.Commons
import qs.Ui

// One list in the settings: name, type, path, whether it counts in the bar,
// and a remove button. Text edits are reported when the field is left, not on
// every key.
Column {
  id: root

  property var entry: ({})
  property string fontFamily: Style.font.family

  signal edited(var entry)
  signal removed()

  spacing: Style.space(8)

  function update(key, value) {
    var next = {}
    for (var k in root.entry)
      next[k] = root.entry[k]
    next[key] = value
    root.edited(next)
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    TextField {
      id: nameField

      width: parent.width - typeChoice.width - removeButton.width - parent.spacing * 2
      text: root.entry.name || ""
      placeholderText: qsTr("Tab name")
      font.family: root.fontFamily
      onEditingFinished: if (text.trim() !== root.entry.name) root.update("name", text.trim())
    }

    Dropdown {
      id: typeChoice

      width: Style.space(120)
      showLabel: false
      value: root.entry.type || "checklist"
      options: [
        { value: "folder", label: qsTr("folder") },
        { value: "checklist", label: qsTr("checklist") },
        { value: "sections", label: qsTr("sections") }
      ]
      fontFamily: root.fontFamily
      onChanged: function (value) { if (value !== root.entry.type) root.update("type", value) }
    }

    RowButton {
      id: removeButton

      anchors.verticalCenter: nameField.verticalCenter
      glyph: ""
      label: qsTr("Remove this list")
      fontFamily: root.fontFamily
      onClicked: root.removed()
    }
  }

  TextField {
    width: parent.width
    text: root.entry.path || ""
    placeholderText: root.entry.type === "folder" ? qsTr("Folder in the vault, for example Read Later") : qsTr("File in the vault, for example Todo.md")
    font.family: root.fontFamily
    onEditingFinished: if (text.trim() !== root.entry.path) root.update("path", text.trim())
  }

  Toggle {
    width: parent.width
    label: qsTr("Count in the bar")
    checked: root.entry.badge === undefined ? root.entry.type !== "sections" : root.entry.badge
    fontFamily: root.fontFamily
    onClicked: root.update("badge", !checked)
  }
}
