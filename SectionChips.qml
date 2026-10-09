import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The sections of a new notes file, as chips: remove one, or type a new one.
Flow {
  id: root

  property var sections: []
  property string fontFamily: Style.font.family

  signal edited(var sections)

  spacing: Style.space(6)

  Repeater {
    model: root.sections

    delegate: Rectangle {
      required property string modelData
      required property int index

      width: chipRow.implicitWidth + Style.space(16)
      height: Style.space(30)
      radius: Style.space(7)
      color: Util.alpha(Commons.Color.popups.text, 0.1)

      Row {
        id: chipRow

        anchors.centerIn: parent
        spacing: Style.space(6)

        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData; textFormat: Text.PlainText; color: Commons.Color.popups.text; font.family: root.fontFamily; font.pixelSize: Style.font.body }

        RowButton {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(20)
          height: Style.space(20)
          glyph: ""
          label: qsTr("Remove section %1").arg(modelData)
          fontFamily: root.fontFamily
          onClicked: root.edited(root.sections.filter(function (s, i) { return i !== index }))
        }
      }
    }
  }

  TextField {
    width: Style.space(150)
    placeholderText: qsTr("+ section")
    font.family: root.fontFamily
    onAccepted: {
      var name = text.trim()
      if (name !== "" && root.sections.indexOf(name) < 0)
        root.edited(root.sections.concat([name]))
      clear()
    }
  }
}
