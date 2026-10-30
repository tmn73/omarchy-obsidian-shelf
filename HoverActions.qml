import QtQuick
import qs.Commons
import "Motion.js" as Motion

// The edit and remove buttons a row shows on hover or under the keyboard
// highlight.
Row {
  id: root

  property bool shown: false
  property string fontFamily: Style.font.family

  signal editClicked()
  signal removeClicked()

  spacing: Style.space(2)
  opacity: shown ? 1 : 0
  enabled: shown

  Behavior on opacity { NumberAnimation { duration: Motion.ms(Style, 150) } }

  RowButton {
    glyph: ""
    label: qsTr("Edit")
    fontFamily: root.fontFamily
    onClicked: root.editClicked()
  }

  RowButton {
    glyph: ""
    label: qsTr("Remove")
    danger: true
    fontFamily: root.fontFamily
    onClicked: root.removeClicked()
  }
}
