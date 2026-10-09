import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Board.js" as Board

// One card of a board: its box, its text, its date, and on hover or under the
// keyboard highlight the move, date, edit and remove buttons. The date panel
// opens under the card.
Column {
  id: root

  property string key: ""
  property string text: ""
  property string date: ""
  property string time: ""
  property bool checked: false
  property string lane: ""
  property Item board: null
  property bool accent: false
  property string fontFamily: Style.font.family

  // An empty key never matches: "" is also what the board holds when no card
  // is current, edited or dated.
  readonly property bool current: key !== "" && board !== null && board.currentKey === key
  readonly property bool editing: key !== "" && board !== null && board.editingKey === key
  readonly property bool dating: key !== "" && board !== null && board.datingKey === key
  readonly property bool choosing: key !== "" && board !== null && board.statusKey === key
  readonly property var label: Board.dateLabel({ date: date, time: time, checked: checked }, board ? board.today : "", board ? board.datesOn : true)

  spacing: Style.space(4)

  // The status menu floats at the board level; the card tells it where its
  // button is, whether the menu opened from a click or from the s key.
  onChoosingChanged: if (choosing && board) board.anchorStatus(statusButton)

  Item {
    width: parent.width
    implicitHeight: Math.max(label.implicitHeight, Style.space(22)) + Style.space(18)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(9)
      color: hover.hovered || root.current || root.dating || root.choosing ? Util.alpha(Commons.Color.popups.text, 0.07) : root.accent ? Util.alpha(Commons.Color.accent, 0.06) : Util.alpha(Commons.Color.popups.text, 0.03)

      Behavior on color { ColorAnimation { duration: Style.duration(150) } }
    }

    HoverHandler { id: hover }

    MouseArea {
      id: box

      x: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      height: width
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      Accessible.role: Accessible.CheckBox
      Accessible.name: root.checked ? qsTr("Back to the first lane: %1").arg(root.text) : qsTr("Done: %1").arg(root.text)
      onClicked: root.board.tick(root.key)

      Rectangle {
        anchors.fill: parent
        radius: Style.space(6)
        color: root.checked ? Commons.Color.accent : "transparent"
        border.width: Math.max(1, Style.space(1.5))
        border.color: root.checked || box.containsMouse ? Commons.Color.accent : Util.alpha(Commons.Color.popups.text, 0.4)
      }

      Text {
        anchors.centerIn: parent
        visible: root.checked
        text: ""
        textFormat: Text.PlainText
        color: Commons.Color.popups.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Loader {
      anchors.left: box.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      active: root.editing
      visible: active
      sourceComponent: InlineEditor {
        initialText: root.text
        font.family: root.fontFamily
        onSaved: function (text) { root.board.save(root.key, text) }
        onCancelled: root.board.editingKey = ""
      }
    }

    // The text keeps the whole width, so the card never changes height on
    // hover; while the buttons show, the text is cut just before them.
    Item {
      id: textClip

      visible: !root.editing
      anchors.left: box.right
      anchors.leftMargin: Style.space(12)
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: actions.opacity > 0 ? Math.max(0, actions.x - x - Style.space(10)) : fullWidth
      clip: true

      readonly property real fullWidth: parent.width - x - Style.space(10)

      Row {
        width: textClip.fullWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Text {
          id: label

          width: Math.min(implicitWidth, parent.width - (chip.visible ? chip.width + parent.spacing : 0))
          anchors.verticalCenter: parent.verticalCenter
          text: root.text
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.checked ? Util.alpha(Commons.Color.popups.text, 0.5) : Commons.Color.popups.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.strikeout: root.checked
        }

        DateChip {
          id: chip

          anchors.verticalCenter: parent.verticalCenter
          visible: root.label.text !== ""
          text: root.label.text
          tone: root.label.tone
          fontFamily: root.fontFamily
        }
      }
    }

    Row {
      id: actions

      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      opacity: (hover.hovered || root.current || root.dating || root.choosing) && !root.editing ? 1 : 0
      enabled: opacity > 0

      Behavior on opacity { NumberAnimation { duration: Style.duration(150) } }

      MouseArea {
        id: statusButton

        anchors.verticalCenter: parent.verticalCenter
        width: statusLabel.implicitWidth + Style.space(18)
        height: Style.space(30)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Status: %1").arg(root.lane)
        onClicked: root.board.toggleStatus(root.key)

        Rectangle {
          anchors.fill: parent
          radius: Style.space(7)
          color: statusButton.containsMouse || root.choosing ? Util.alpha(Commons.Color.popups.text, 0.14) : Util.alpha(Commons.Color.popups.text, 0.06)
        }

        Text {
          id: statusLabel

          anchors.centerIn: parent
          text: root.lane + "  "
          textFormat: Text.PlainText
          color: Util.alpha(Commons.Color.popups.text, 0.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      RowButton { visible: root.board !== null && root.board.datesOn; glyph: ""; label: qsTr("Date"); fontFamily: root.fontFamily; onClicked: root.board.toggleDate(root.key) }
      RowButton { glyph: ""; label: qsTr("Edit"); fontFamily: root.fontFamily; onClicked: root.board.editingKey = root.key }
      RowButton { glyph: ""; label: qsTr("Remove"); danger: true; fontFamily: root.fontFamily; onClicked: root.board.remove(root.key) }
    }
  }

  Loader {
    width: parent.width
    active: root.dating
    visible: active
    sourceComponent: DatePanel {
      date: root.date
      time: root.time
      today: root.board.today
      fontFamily: root.fontFamily
      onPicked: function (date, time) { root.board.setDate(root.key, date, time) }
      onCancelled: root.board.datingKey = ""
    }
  }
}
