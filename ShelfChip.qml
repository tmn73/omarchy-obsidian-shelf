import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The bar chip: the shelf glyph, and what waits in the lists that notify.
//
// The count is a reminder: it stays while the items exist, and the glyph
// stands alone when nothing waits. A new item makes the count enter from
// above and an accent dot ping three times; the dot then stays until the
// popup has been seen. The count turns the urgent color while a board card
// is late. A dot in the urgent color means the sync stopped.
//
// With items given, the chip becomes a pill in the accent color that shows
// them one at a time beside the count: a line fills along the bottom, then
// the next item slides up and the pill glows for a moment.
WidgetButton {
  id: root

  property int count: 0
  property bool pinging: false
  property bool marked: false
  property bool urgent: false
  property bool late: false
  property var items: []
  property int itemIndex: 0

  readonly property int itemInterval: 6000
  readonly property string currentItem: items.length > 0 ? String(items[itemIndex % items.length]) : ""
  readonly property bool showItems: currentItem !== "" && !vertical
  readonly property color tint: late ? Commons.Color.urgent : Commons.Color.accent
  property real progress: 0
  property real glow: 0

  readonly property string glyph: ""

  // The inherited label only sizes the button; the row below draws it so the
  // count can animate on its own.
  text: count > 0 ? glyph + "  " + count : glyph
  labelVisible: false
  fixedWidth: showItems ? pill.width + Style.space(8) : -1

  onItemsChanged: if (itemIndex >= items.length) itemIndex = 0

  function tinted(alpha) {
    return Qt.rgba(tint.r, tint.g, tint.b, alpha)
  }

  // Sized to the longest item, so the bar does not shift at each swap.
  TextMetrics {
    id: longestItem

    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: true
    text: root.items.reduce(function (a, b) { return String(b).length > a.length ? String(b) : a }, "")
  }

  Timer {
    interval: root.itemInterval
    repeat: true
    running: root.showItems && root.items.length > 1
    onRunningChanged: if (running) fill.restart()
    onTriggered: swap.restart()
  }

  NumberAnimation {
    id: fill

    target: root
    property: "progress"
    from: 0
    to: 1
    duration: Style.duration(root.itemInterval)
  }

  SequentialAnimation {
    id: swap

    ParallelAnimation {
      NumberAnimation { target: itemShift; property: "y"; to: -itemClip.height * 0.6; duration: Style.duration(220); easing.type: Easing.InCubic }
      NumberAnimation { target: itemText; property: "opacity"; to: 0; duration: Style.duration(220) }
    }
    ScriptAction {
      script: {
        root.itemIndex = (root.itemIndex + 1) % Math.max(1, root.items.length)
        itemShift.y = itemClip.height * 0.6
        fill.restart()
      }
    }
    ParallelAnimation {
      NumberAnimation { target: itemShift; property: "y"; to: 0; duration: Style.duration(320); easing.type: Easing.OutBack }
      NumberAnimation { target: itemText; property: "opacity"; to: 1; duration: Style.duration(260) }
      NumberAnimation { target: root; property: "glow"; from: 1; to: 0; duration: Style.duration(900); easing.type: Easing.OutCubic }
    }
  }

  Rectangle {
    id: pill

    visible: root.showItems
    anchors.centerIn: parent
    width: content.implicitWidth + Style.space(22)
    height: Math.max(content.implicitHeight + Style.space(6), root.height - Style.space(8))
    radius: height / 2
    clip: true
    color: root.tinted(0.24 + 0.3 * root.glow)
    border.width: 1
    border.color: root.tinted(0.75 + 0.25 * root.glow)

    Rectangle {
      visible: root.items.length > 1
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.leftMargin: parent.radius
      anchors.bottomMargin: 2
      width: (parent.width - parent.radius * 2) * root.progress
      height: 2
      radius: 1
      color: root.tint
    }
  }
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
      color: root.showItems ? root.tint : root.foreground
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
        color: Commons.Color.accent
        visible: root.pinging || root.marked

        Rectangle {
          id: halo

          anchors.centerIn: parent
          width: parent.width
          height: width
          radius: width / 2
          color: "transparent"
          border.width: Math.max(1, Style.space(1))
          border.color: Commons.Color.accent
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
      color: root.late ? Commons.Color.urgent : (root.showItems ? root.tint : root.foreground)
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: true
      renderType: Text.NativeRendering
      transform: Translate { id: countShift }
    }

    Rectangle {
      visible: root.showItems
      width: 1
      height: itemClip.height * 0.7
      anchors.verticalCenter: parent.verticalCenter
      color: root.tinted(0.5)
    }

    Item {
      id: itemClip

      visible: root.showItems
      clip: true
      width: Math.min(Style.space(260), Math.ceil(longestItem.advanceWidth) + 1)
      height: itemText.implicitHeight

      Text {
        id: itemText

        width: parent.width
        text: root.currentItem
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: true
        renderType: Text.NativeRendering
        transform: Translate { id: itemShift }
      }
    }
  }

  Rectangle {
    width: Style.space(6)
    height: width
    radius: width / 2
    anchors.right: content.right
    anchors.bottom: content.bottom
    anchors.rightMargin: -width / 2
    color: Commons.Color.urgent
    visible: root.urgent
  }

  ParallelAnimation {
    id: bump

    NumberAnimation { target: countShift; property: "y"; from: -Style.space(8); to: 0; duration: Style.duration(500); easing.type: Easing.OutBack }
    NumberAnimation { target: countText; property: "opacity"; from: 0; to: 1; duration: Style.duration(300); easing.type: Easing.OutCubic }
  }
}
