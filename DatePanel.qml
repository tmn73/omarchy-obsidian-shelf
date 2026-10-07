import QtQuick
import qs.Commons
import qs.Ui
import "Board.js" as Board

// The date panel under a card: quick picks, a date and a time, or no date.
Rectangle {
  id: root

  property string date: ""
  property string time: ""
  property string today: ""
  property string fontFamily: Style.font.family
  property string error: ""

  signal picked(string date, string time)
  signal cancelled()

  readonly property var quickPicks: [
    { label: qsTr("Today"), date: root.today },
    { label: qsTr("Tomorrow"), date: Board.shiftDay(root.today, 1) },
    { label: qsTr("Next Monday"), date: Board.nextMonday(root.today) },
    { label: qsTr("In a week"), date: Board.shiftDay(root.today, 7) }
  ]

  implicitHeight: body.implicitHeight + Style.space(20)
  radius: Style.space(10)
  color: Util.alpha(Color.popups.text, 0.06)
  border.width: 1
  border.color: Util.alpha(Color.popups.text, 0.14)

  // The popup keys are off while the panel is open, so the date field takes
  // the focus at once: Escape then closes the panel, Enter sets the date.
  Component.onCompleted: dateField.forceActiveFocus()

  function apply() {
    var d = dateField.text.trim()
    var t = timeField.text.trim()
    if ((d !== "" && !/^\d{4}-\d{2}-\d{2}$/.test(d)) || (t !== "" && !/^([01]\d|2[0-3]):[0-5]\d$/.test(t))) {
      error = qsTr("Write the date as 2026-10-20 and the time as 14:30.")
      return
    }
    root.picked(d, t)
  }

  Column {
    id: body

    x: Style.space(10)
    y: Style.space(10)
    width: parent.width - Style.space(20)
    spacing: Style.space(8)

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: root.quickPicks

        delegate: Button {
          required property var modelData

          text: modelData.label
          // A pick fills the date and leaves room for a time; Set applies.
          onClicked: {
            dateField.text = modelData.date
            root.error = ""
            timeField.forceActiveFocus()
          }
        }
      }
    }

    Row {
      spacing: Style.space(8)

      TextField {
        id: dateField

        width: Style.space(130)
        text: root.date
        placeholderText: qsTr("2026-10-20")
        font.family: root.fontFamily
        onAccepted: root.apply()
        Keys.onEscapePressed: root.cancelled()
      }

      TextField {
        id: timeField

        width: Style.space(80)
        text: root.time
        placeholderText: qsTr("14:30")
        font.family: root.fontFamily
        onAccepted: root.apply()
        Keys.onEscapePressed: root.cancelled()
      }

      Button { text: qsTr("Set"); bordered: true; background: Color.accent; foreground: Color.popups.background; onClicked: root.apply() }
      Button { text: qsTr("No date"); onClicked: root.picked("", "") }
    }

    Text {
      width: parent.width
      text: root.error !== "" ? root.error : qsTr("A card with a time rings at that time. A card with only a date is in the morning summary.")
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.error !== "" ? Color.urgent : Util.alpha(Color.popups.text, 0.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
