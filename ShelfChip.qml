import QtQuick
import qs.Commons
import qs.Ui

// The bar chip: the shelf glyph and the open count.
//
// The count enters from above and an accent dot pings three times when a new
// item lands in a list that counts. A dot in the urgent color means the sync
// check fails, which is the only state that deserves an alarm color.
WidgetButton {
  id: root

  property int count: 0
  property bool pinging: false
  property bool urgent: false

  readonly property string glyph: ""

  // The inherited label only sizes the button; the row below draws it so the
  // count can animate on its own.
  text: count > 0 ? glyph + "  " + count : glyph
  labelVisible: false
  dimmed: count === 0 && !urgent

  onPingingChanged: if (pinging) bump.restart()

  Row {
    id: content

    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyphText

      text: root.glyph
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      renderType: Text.NativeRendering

      Rectangle {
        id: pingDot

        width: Style.space(6)
        height: width
        radius: width / 2
        x: parent.width - width / 2
        y: -height / 3
        color: Color.accent
        visible: root.pinging

        Rectangle {
          id: halo

          anchors.centerIn: parent
          width: parent.width
          height: width
          radius: width / 2
          color: "transparent"
          border.width: Math.max(1, Style.space(1))
          border.color: Color.accent
        }

        SequentialAnimation {
          running: root.pinging
          loops: 3
          ParallelAnimation {
            NumberAnimation { target: halo; property: "scale"; from: 1; to: 2.6; duration: Style.duration(1100); easing.type: Easing.OutCubic }
            NumberAnimation { target: halo; property: "opacity"; from: 1; to: 0; duration: Style.duration(1100); easing.type: Easing.OutCubic }
          }
        }
      }
    }

    Text {
      id: countText

      visible: root.count > 0
      text: String(root.count)
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: true
      renderType: Text.NativeRendering
      transform: Translate { id: countShift }
    }
  }

  Rectangle {
    width: Style.space(6)
    height: width
    radius: width / 2
    anchors.right: content.right
    anchors.bottom: content.bottom
    anchors.rightMargin: -width / 2
    color: Color.urgent
    visible: root.urgent
  }

  ParallelAnimation {
    id: bump

    NumberAnimation { target: countShift; property: "y"; from: -Style.space(8); to: 0; duration: Style.duration(500); easing.type: Easing.OutBack }
    NumberAnimation { target: countText; property: "opacity"; from: 0; to: 1; duration: Style.duration(300); easing.type: Easing.OutCubic }
  }
}
