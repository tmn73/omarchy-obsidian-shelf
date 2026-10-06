import QtQuick
import qs.Commons
import "Model.js" as Model

// One lane of a board: its title and count, then its cards. A Complete lane
// folds, with a toggle and a Clear button in its title row.
Column {
  id: root

  property var lane: ({ title: "", complete: false, items: [] })
  property Item board: null
  property bool accent: false
  property bool folded: false
  property string fontFamily: Style.font.family

  readonly property var items: Model.toArray(lane.items) || []

  spacing: Style.space(6)

  onItemsChanged: view.syncItems(items)
  Component.onCompleted: view.syncItems(items)

  Row {
    width: parent.width
    height: Style.space(28)
    spacing: Style.space(8)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      radius: width / 2
      color: root.accent ? Color.accent : Util.alpha(Color.popups.text, root.lane.complete ? 0.25 : 0.5)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.lane.title.toUpperCase()
      textFormat: Text.PlainText
      color: Util.alpha(Color.popups.text, 0.75)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      font.letterSpacing: Style.space(1.5)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: String(root.items.length)
      textFormat: Text.PlainText
      color: Util.alpha(Color.popups.text, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: parent.width - x - (laneTools.visible ? laneTools.width : 0)
      height: 1
    }

    Row {
      id: laneTools

      visible: root.lane.complete
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      MouseArea {
        visible: root.items.length > 0
        width: clearLabel.implicitWidth + Style.space(16)
        height: Style.space(26)
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Clear the done cards")
        onClicked: root.board.clearDone()

        Rectangle {
          anchors.fill: parent
          radius: Style.space(6)
          color: "transparent"
          border.width: 1
          border.color: parent.containsMouse ? Color.urgent : Util.alpha(Color.popups.text, 0.2)
        }

        Text {
          id: clearLabel

          anchors.centerIn: parent
          text: qsTr("Clear")
          textFormat: Text.PlainText
          color: parent.containsMouse ? Color.urgent : Util.alpha(Color.popups.text, 0.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      RowButton {
        width: Style.space(26)
        height: Style.space(26)
        glyph: root.folded ? "" : ""
        label: root.folded ? qsTr("Show the done cards") : qsTr("Hide the done cards")
        fontFamily: root.fontFamily
        onClicked: root.board.doneOpen = !root.board.doneOpen
      }
    }
  }

  ShelfListView {
    id: view

    width: parent.width
    height: contentHeight
    visible: !root.folded
    interactive: false
    spacing: Style.space(6)

    delegate: CardRow {
      required key
      required text
      required date
      required time
      required checked
      required lane

      width: view.width
      board: root.board
      accent: root.accent
      fontFamily: root.fontFamily
    }
  }

  DashedBox {
    width: parent.width
    visible: !root.folded && root.items.length === 0
    text: qsTr("Nothing here")
    fontFamily: root.fontFamily
  }
}
