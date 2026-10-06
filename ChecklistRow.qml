import QtQuick
import qs.Commons

// One todo. A tick fills the box, draws the check and strikes the text; the
// row then asks the list to remove it, so the leave motion follows the tick.
// Edit and remove show on hover.
Item {
  id: root

  property string text: ""
  property bool current: false
  property string fontFamily: Style.font.family
  property bool ticking: false
  property bool editing: false

  signal tickRequested()
  signal removeRequested()
  signal editRequested()
  signal saved(string text)
  signal cancelled()

  function startEdit() {
    root.editRequested()
  }

  implicitHeight: Math.max(label.implicitHeight, box.height) + Style.space(18)

  function tick() {
    if (ticking)
      return
    ticking = true
    tickMotion.start()
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.space(9)
    color: hover.hovered || root.current ? Util.alpha(Color.popups.text, 0.05) : "transparent"

    Behavior on color { ColorAnimation { duration: Style.duration(150) } }
  }

  HoverHandler {
    id: hover
  }

  MouseArea {
    id: box

    x: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(22)
    height: width
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: qsTr("Done: %1").arg(root.text)
    onClicked: root.tick()

    Rectangle {
      id: boxFill

      anchors.fill: parent
      radius: Style.space(6)
      color: root.ticking ? Color.accent : "transparent"
      border.width: Math.max(1, Style.space(1.5))
      border.color: root.ticking || box.containsMouse ? Color.accent : Util.alpha(Color.popups.text, 0.4)

      Behavior on color { ColorAnimation { duration: Style.duration(200) } }
      Behavior on border.color { ColorAnimation { duration: Style.duration(200) } }
    }

    Item {
      id: checkClip

      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      width: 0
      clip: true

      Text {
        x: (box.width - implicitWidth) / 2
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        textFormat: Text.PlainText
        color: Color.popups.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  HoverActions {
    id: actions

    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    shown: (hover.hovered || root.current) && !root.ticking && !root.editing
    fontFamily: root.fontFamily
    onEditClicked: root.startEdit()
    onRemoveClicked: root.removeRequested()
  }

  Loader {
    anchors.left: box.right
    anchors.leftMargin: Style.space(12)
    anchors.right: actions.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    active: root.editing
    visible: active
    sourceComponent: InlineEditor {
      initialText: root.text
      font.family: root.fontFamily
      onSaved: function (text) { root.saved(text) }
      onCancelled: root.cancelled()
    }
  }

  Text {
    id: label

    visible: !root.editing
    anchors.left: box.right
    anchors.leftMargin: Style.space(12)
    anchors.right: actions.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.text
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: root.ticking ? Util.alpha(Color.popups.text, 0.55) : Color.popups.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.body

    Behavior on color { ColorAnimation { duration: Style.duration(300) } }

    Rectangle {
      id: strike

      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(1, Style.space(1))
      width: 0
      color: Util.alpha(Color.popups.text, 0.55)
    }
  }

  SequentialAnimation {
    id: tickMotion

    ParallelAnimation {
      NumberAnimation { target: checkClip; property: "width"; to: box.width; duration: Style.duration(350); easing.type: Easing.OutCubic }
      SequentialAnimation {
        PauseAnimation { duration: Style.duration(150) }
        NumberAnimation { target: strike; property: "width"; to: Math.min(label.implicitWidth, label.width); duration: Style.duration(350); easing.type: Easing.OutCubic }
      }
    }
    ScriptAction { script: root.tickRequested() }
  }
}
