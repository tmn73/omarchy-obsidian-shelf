import QtQuick
import qs.Commons
import qs.Commons as Commons

// Two-step clear. The first click arms the button: it turns to the urgent
// color and a bar drains over three seconds. A second click before the bar is
// empty confirms; otherwise the button disarms on its own.
MouseArea {
  id: root

  property int count: 0
  property string listName: ""
  property string fontFamily: Style.font.family
  property bool armed: false

  signal confirmed()

  height: Style.space(38)
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  enabled: count > 0
  opacity: enabled ? 1 : 0.45
  Accessible.role: Accessible.Button
  Accessible.name: label.text

  onClicked: {
    if (!armed) {
      armed = true
      drain.restart()
      disarm.restart()
      return
    }
    disarm.stop()
    drain.stop()
    armed = false
    root.confirmed()
  }

  Timer {
    id: disarm

    interval: Style.duration(3000) > 0 ? Style.duration(3000) : 3000
    onTriggered: root.armed = false
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.space(8)
    clip: true
    color: root.armed ? Util.alpha(Commons.Color.urgent, 0.12) : "transparent"
    border.width: Math.max(1, Style.space(1))
    border.color: root.armed ? Commons.Color.urgent : Util.alpha(Commons.Color.popups.text, root.containsMouse ? 0.5 : 0.2)

    Behavior on color { ColorAnimation { duration: Style.duration(200) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(200) } }

    Rectangle {
      id: drainBar

      anchors.left: parent.left
      anchors.bottom: parent.bottom
      height: Math.max(2, Style.space(2))
      width: 0
      color: Commons.Color.urgent
      visible: root.armed
    }
  }

  NumberAnimation {
    id: drain

    target: drainBar
    property: "width"
    from: root.width
    to: 0
    duration: Style.duration(3000)
  }

  Text {
    id: label

    anchors.centerIn: parent
    text: root.armed ? qsTr("Click again to clear %1 items").arg(root.count) : qsTr("Clear after %1").arg(root.listName.toLowerCase())
    textFormat: Text.PlainText
    color: root.armed || root.containsMouse ? Commons.Color.popups.text : Util.alpha(Commons.Color.popups.text, 0.65)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
