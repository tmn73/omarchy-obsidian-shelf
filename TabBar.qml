import QtQuick
import qs.Commons

// Tabs, one per list, each with its count. When the names fit, the tabs fill
// the bar. When they do not, each tab keeps the width of its name and the bar
// scrolls sideways, with the active tab always scrolled into view. The accent
// indicator springs to the active tab.
Item {
  id: root

  property var tabs: []          // [{ name, count }]
  property int currentIndex: 0
  property string fontFamily: Style.font.family

  signal activated(int index)

  readonly property real inset: Style.space(3)
  readonly property real viewWidth: width - inset * 2
  readonly property Item activeTab: repeater.count > 0 ? repeater.itemAt(Math.min(currentIndex, repeater.count - 1)) : null
  readonly property real namesWidth: {
    var sum = 0
    for (var i = 0; i < repeater.count; i++) {
      var tab = repeater.itemAt(i)
      if (tab)
        sum += tab.nameWidth
    }
    return sum
  }
  // The room left when every name fits, shared by the tabs.
  readonly property real spare: repeater.count > 0 && namesWidth < viewWidth ? (viewWidth - namesWidth) / repeater.count : 0
  readonly property bool overflows: flick.contentWidth > flick.width + 1

  implicitHeight: Style.space(40)

  function ensureVisible() {
    if (!activeTab)
      return
    var margin = Style.space(28)
    var target = flick.contentX
    if (activeTab.x - margin < target)
      target = activeTab.x - margin
    else if (activeTab.x + activeTab.width + margin > target + flick.width)
      target = activeTab.x + activeTab.width + margin - flick.width
    target = Math.max(0, Math.min(target, flick.contentWidth - flick.width))
    if (target === flick.contentX)
      return
    scroll.to = target
    scroll.restart()
  }

  onCurrentIndexChanged: Qt.callLater(ensureVisible)
  onActiveTabChanged: Qt.callLater(ensureVisible)
  onWidthChanged: Qt.callLater(ensureVisible)

  Rectangle {
    anchors.fill: parent
    radius: Style.space(9)
    color: Util.alpha(Color.popups.text, 0.04)
    border.width: 1
    border.color: Util.alpha(Color.popups.text, 0.08)
  }

  Flickable {
    id: flick

    x: root.inset
    y: root.inset
    width: root.viewWidth
    height: root.height - root.inset * 2
    contentWidth: row.width
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    NumberAnimation {
      id: scroll

      target: flick
      property: "contentX"
      duration: Style.duration(260)
      easing.type: Easing.OutCubic
    }

    // A mouse wheel scrolls the tabs sideways when they do not fit.
    WheelHandler {
      enabled: root.overflows
      onWheel: function (event) {
        var delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
        flick.contentX = Math.max(0, Math.min(flick.contentX - delta, flick.contentWidth - flick.width))
      }
    }

    Rectangle {
      x: root.activeTab ? root.activeTab.x : 0
      width: root.activeTab ? root.activeTab.width : 0
      height: flick.height
      radius: Style.space(6)
      color: Color.accent
      visible: root.activeTab !== null

      Behavior on x {
        NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutBack; easing.overshoot: 1.4 }
      }
      Behavior on width {
        NumberAnimation { duration: Style.duration(380); easing.type: Easing.OutCubic }
      }
    }

    Row {
      id: row

      height: flick.height

      Repeater {
        id: repeater

        model: root.tabs

        delegate: MouseArea {
          id: tab

          required property var modelData
          required property int index
          readonly property bool active: index === root.currentIndex
          // From the text and the count, not from the Row: a Row has no implicit width.
          readonly property real nameWidth: nameLabel.implicitWidth + content.spacing + countPill.width + Style.space(24)

          width: nameWidth + root.spare
          height: row.height
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activated(index)

          Row {
            id: content

            anchors.centerIn: parent
            spacing: Style.space(7)

            Text {
              id: nameLabel

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
              id: countPill

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

  // A thin scroll bar shows that more tabs wait to the side.
  Rectangle {
    visible: root.overflows
    x: flick.x + flick.visibleArea.xPosition * flick.width
    y: root.height - height - Style.space(1)
    width: flick.visibleArea.widthRatio * flick.width
    height: Style.space(2)
    radius: height / 2
    color: Util.alpha(Color.popups.text, 0.35)
  }
}
