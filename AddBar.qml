import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The add field. With sections, a picker chooses where the new line goes;
// the first section is picked by default.
Column {
  id: root

  property var sections: []
  property string placeholder: qsTr("New item")
  property string fontFamily: Style.font.family
  property string section: sections.length > 0 ? sections[0] : ""
  property bool inputFocused: field.activeFocus

  signal submitted(string text, string section)

  spacing: Style.space(8)

  onSectionsChanged: if (sections.indexOf(section) < 0) section = sections.length > 0 ? sections[0] : ""

  function focusInput() {
    field.forceActiveFocus()
  }

  function submit() {
    var text = field.text.trim()
    if (text === "")
      return
    root.submitted(text, root.section)
    field.clear()
  }

  Row {
    visible: root.sections.length > 0
    spacing: Style.space(4)

    Repeater {
      model: root.sections

      delegate: MouseArea {
        required property string modelData
        readonly property bool picked: modelData === root.section

        width: segLabel.implicitWidth + Style.space(20)
        height: Style.space(30)
        cursorShape: Qt.PointingHandCursor
        onClicked: root.section = modelData

        Rectangle {
          anchors.fill: parent
          radius: Style.space(6)
          color: parent.picked ? Util.alpha(Commons.Color.popups.text, 0.14) : "transparent"

          Behavior on color { ColorAnimation { duration: Style.duration(200) } }
        }

        Text {
          id: segLabel

          anchors.centerIn: parent
          text: modelData
          textFormat: Text.PlainText
          color: parent.picked ? Commons.Color.popups.text : Util.alpha(Commons.Color.popups.text, 0.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    TextField {
      id: field

      width: parent.width - addButton.width - parent.spacing
      placeholderText: root.placeholder
      font.family: root.fontFamily
      onAccepted: root.submit()
      Keys.onEscapePressed: field.focus = false
    }

    MouseArea {
      id: addButton

      width: addLabel.implicitWidth + Style.space(28)
      height: field.height
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      Accessible.role: Accessible.Button
      Accessible.name: "Add"
      onClicked: root.submit()

      Rectangle {
        anchors.fill: parent
        radius: Style.space(8)
        color: addButton.containsMouse ? Commons.Color.accent : Util.alpha(Commons.Color.popups.text, 0.1)

        Behavior on color { ColorAnimation { duration: Style.duration(150) } }
      }

      Text {
        id: addLabel

        anchors.centerIn: parent
        text: "Add"
        textFormat: Text.PlainText
        color: addButton.containsMouse ? Commons.Color.popups.background : Commons.Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }
  }
}
