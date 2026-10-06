import QtQuick
import qs.Commons

// Segmented tabs, one per list, each with its count. The accent indicator
// springs to the active tab.
Item {
  id: root

  property var tabs: []          // [{ name, count }]
  property int currentIndex: 0
  property string fontFamily: Style.font.family

  signal activated(int index)

  readonly property int tabCount: Math.max(1, tabs.length)
  readonly property real inset: Style.space(3)
  readonly property real tabWidth: (width - inset * 2) / tabCount

  implicitHeight: Style.space(40)

  Rectangle {
    anchors.fill: parent
    radius: Style.space(9)
    color: Util.alpha(Color.popups.text, 0.04)
    border.width: 1
    border.color: Util.alpha(Color.popups.text, 0.08)
  }

  Rectangle {
    id: indicator

    x: root.inset + root.currentIndex * root.tabWidth
    y: root.inset
    width: root.tabWidth
    height: root.height - root.inset * 2
    radius: Style.space(6)
    color: Color.accent
    visible: root.tabs.length > 0

    Behavior on x {
      NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutBack; easing.overshoot: 1.4 }
    }
  }

  Row {
    x: root.inset
    y: root.inset
    height: root.height - root.inset * 2

    Repeater {
      model: root.tabs

      delegate: MouseArea {
        id: tab

        required property var modelData
        required property int index
        readonly property bool active: index === root.currentIndex

        width: root.tabWidth
        height: parent.height
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated(index)

        Row {
          anchors.centerIn: parent
          spacing: Style.space(7)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: tab.modelData.name
            textFormat: Text.PlainText
            color: tab.active ? Color.popups.background : Util.alpha(Color.popups.text, 0.65)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: tab.active

            Behavior on color { ColorAnimation { duration: Style.duration(250) } }
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: countLabel.implicitWidth + Style.space(12)
            height: countLabel.implicitHeight + Style.space(2)
            radius: height / 2
            color: tab.active ? Util.alpha(Color.popups.background, 0.18) : Util.alpha(Color.popups.text, 0.08)

            Text {
              id: countLabel

              anchors.centerIn: parent
              text: String(tab.modelData.count)
              textFormat: Text.PlainText
              color: tab.active ? Color.popups.background : Color.popups.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
