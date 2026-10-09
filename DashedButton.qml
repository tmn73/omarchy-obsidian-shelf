import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// A dashed, full-width button for adding something.
MouseArea {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family

  height: Style.space(44)
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  Accessible.role: Accessible.Button
  Accessible.name: text

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.containsMouse ? Commons.Color.accent : Util.alpha(Commons.Color.popups.text, 0.3)
      strokeWidth: Math.max(1, Style.space(1.5))
      strokeStyle: ShapePath.DashLine
      dashPattern: [3, 3]
      fillColor: "transparent"

      PathRectangle { x: 1; y: 1; width: root.width - 2; height: root.height - 2; radius: Style.space(10) }
    }
  }

  Text {
    anchors.centerIn: parent
    text: root.text
    textFormat: Text.PlainText
    color: root.containsMouse ? Commons.Color.popups.text : Util.alpha(Commons.Color.popups.text, 0.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
