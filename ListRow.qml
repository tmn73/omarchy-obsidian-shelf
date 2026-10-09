import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// One list in the settings: move it, choose whether it notifies, and open it
// to rename it, point it at another path, or see how to fill it from a phone.
Rectangle {
  id: root

  property var cfg: ({})
  property string detail: ""
  property bool expanded: false
  property bool first: false
  property bool last: false
  property string vaultPath: ""
  property string fontFamily: Style.font.family
  property bool picking: false
  property bool showHow: false

  signal moveUp()
  signal moveDown()
  signal toggleExpand()
  signal changed(string field, var value)
  signal removeRequested()

  readonly property string glyph: cfg.type === "folder" ? "" : cfg.type === "checklist" ? "" : cfg.type === "board" ? "\uf181" : ""

  implicitHeight: column.implicitHeight + Style.space(4)
  radius: Style.space(10)
  color: expanded ? Util.alpha(Commons.Color.popups.text, 0.06) : Util.alpha(Commons.Color.popups.text, 0.04)
  border.width: 1
  border.color: expanded ? Commons.Color.accent : Util.alpha(Commons.Color.popups.text, 0.1)

  onExpandedChanged: if (!expanded) { picking = false; showHow = false }

  Behavior on border.color { ColorAnimation { duration: Style.duration(250) } }

  Column {
    id: column

    width: parent.width
    y: Style.space(2)

    Row {
      width: parent.width
      height: Style.space(56)
      spacing: Style.space(8)
      leftPadding: Style.space(6)

      Column {
        anchors.verticalCenter: parent.verticalCenter

        RowButton { width: Style.space(26); height: Style.space(22); glyph: ""; label: qsTr("Move up"); enabled: !root.first; opacity: enabled ? 1 : 0.3; fontFamily: root.fontFamily; onClicked: root.moveUp() }
        RowButton { width: Style.space(26); height: Style.space(22); glyph: ""; label: qsTr("Move down"); enabled: !root.last; opacity: enabled ? 1 : 0.3; fontFamily: root.fontFamily; onClicked: root.moveDown() }
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        height: width
        radius: Style.space(8)
        color: Util.alpha(Commons.Color.popups.text, 0.1)

        Text { anchors.centerIn: parent; text: root.glyph; textFormat: Text.PlainText; color: Commons.Color.popups.text; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      }

      MouseArea {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(26 + 34 + 30 + 76) - parent.spacing * 4 - Style.space(6)
        height: names.implicitHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleExpand()

        Column {
          id: names

          width: parent.width
          spacing: Style.space(3)

          Text { width: parent.width; text: root.cfg.name || ""; textFormat: Text.PlainText; elide: Text.ElideRight; color: Commons.Color.popups.text; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
          Text { width: parent.width; text: root.detail; textFormat: Text.PlainText; elide: Text.ElideMiddle; color: Util.alpha(Commons.Color.popups.text, 0.65); font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(76)
        spacing: Style.space(2)

        ToggleSwitch {
          anchors.horizontalCenter: parent.horizontalCenter
          checked: root.cfg.badge === true
          accent: Commons.Color.accent
          onToggled: root.changed("badge", !root.cfg.badge)
        }

        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Notify"); textFormat: Text.PlainText; color: Util.alpha(Commons.Color.popups.text, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      }

      RowButton {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        glyph: root.expanded ? "" : ""
        label: root.expanded ? qsTr("Close") : qsTr("Edit")
        fontFamily: root.fontFamily
        onClicked: root.toggleExpand()
      }
    }

    Loader {
      width: parent.width
      active: root.expanded
      visible: active
      sourceComponent: ListRowBody {
        cfg: root.cfg
        vaultPath: root.vaultPath
        fontFamily: root.fontFamily
        picking: root.picking
        showHow: root.showHow
        onChanged: function (field, value) { root.changed(field, value) }
        onPickingToggled: root.picking = !root.picking
        onHowToggled: root.showHow = !root.showHow
        onRemoveRequested: root.removeRequested()
      }
    }
  }
}
