import QtQuick
import qs.Commons
import qs.Ui
import "Board.js" as Board

// The status menu of a card. It floats under the status button, over the
// cards below. A field filters the lanes; a name that is not a lane yet
// becomes "Create". Enter takes the highlighted line, so moving and creating
// are the same gesture.
FocusScope {
  id: root

  property var lanes: []
  property string current: ""
  property string accentLane: ""
  property var completeLanes: []
  property string fontFamily: Style.font.family
  property int highlight: 0

  signal picked(string lane)
  signal created(string lane)
  signal cancelled()

  readonly property var result: Board.statusMatches(lanes, field.text)
  readonly property int rowCount: result.matches.length + (result.canCreate ? 1 : 0)

  width: Style.space(270)
  implicitHeight: frame.height

  function open() {
    field.text = ""
    highlight = 0
    field.forceActiveFocus()
  }

  function choose(index) {
    if (index < result.matches.length)
      root.picked(result.matches[index])
    else if (result.canCreate)
      root.created(field.text.trim())
  }

  function dotColor(lane) {
    if (lane === root.accentLane)
      return Color.accent
    return Util.alpha(Color.popups.text, root.completeLanes.indexOf(lane) >= 0 ? 0.25 : 0.5)
  }

  component MenuRow: MouseArea {
    id: row

    property string label: ""
    property string hint: ""
    property color dot: "transparent"
    property bool lit: false
    property bool create: false

    width: parent ? parent.width : 0
    height: Style.space(34)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    Accessible.role: Accessible.MenuItem
    Accessible.name: label

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: row.lit || row.containsMouse ? Util.alpha(Color.popups.text, 0.1) : "transparent"
    }

    Row {
      anchors.verticalCenter: parent.verticalCenter
      x: Style.space(10)
      spacing: Style.space(10)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: !row.create
        width: Style.space(8)
        height: width
        radius: width / 2
        color: row.dot
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        textFormat: Text.PlainText
        color: row.create ? Color.accent : Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      text: row.hint
      textFormat: Text.PlainText
      color: Util.alpha(Color.popups.text, 0.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    id: frame

    width: parent.width
    height: body.implicitHeight + Style.space(12)
    radius: Style.space(10)
    color: Qt.tint(Color.popups.background, Util.alpha(Color.popups.text, 0.08))
    border.width: 1
    border.color: Util.alpha(Color.popups.text, 0.22)

    Column {
      id: body

      x: Style.space(6)
      y: Style.space(6)
      width: parent.width - Style.space(12)
      spacing: Style.space(2)

      TextField {
        id: field

        width: parent.width
        placeholderText: qsTr("Move to…")
        font.family: root.fontFamily
        onTextChanged: root.highlight = 0
        onAccepted: root.choose(root.highlight)
        Keys.onEscapePressed: root.cancelled()
        Keys.onUpPressed: root.highlight = Math.max(0, root.highlight - 1)
        Keys.onDownPressed: root.highlight = Math.min(root.rowCount - 1, root.highlight + 1)
      }

      Repeater {
        model: root.result.matches

        delegate: MenuRow {
          required property string modelData
          required property int index

          label: modelData
          dot: root.dotColor(modelData)
          lit: index === root.highlight && field.text.trim() !== ""
          hint: modelData === root.current ? qsTr("current") : (lit ? "↵" : "")
          onClicked: root.picked(modelData)
        }
      }

      MenuRow {
        visible: root.result.canCreate
        create: true
        label: qsTr("+ Create “%1”").arg(field.text.trim())
        lit: root.highlight === root.result.matches.length
        hint: lit ? "↵" : ""
        onClicked: root.choose(root.result.matches.length)
      }
    }
  }
}
