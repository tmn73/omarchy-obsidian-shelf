import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// A rounded box with a dashed border and one line of muted text, for an empty
// section.
Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  readonly property real radius: Style.space(8)

  implicitHeight: label.implicitHeight + Style.space(20)

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: Util.alpha(Commons.Color.popups.text, 0.2)
      strokeWidth: Math.max(1, Style.space(1))
      strokeStyle: ShapePath.DashLine
      dashPattern: [3, 3]
      fillColor: "transparent"

      PathRectangle {
        x: 0.5
        y: 0.5
        width: root.width - 1
        height: root.height - 1
        radius: root.radius
      }
    }
  }

  Text {
    id: label

    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: root.text
    textFormat: Text.PlainText
    color: Util.alpha(Commons.Color.popups.text, 0.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
