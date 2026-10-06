import QtQuick
import qs.Commons

// One topic in a section column, with edit and remove on hover.
Rectangle {
  id: root

  property string text: ""
  property bool editing: false
  property string fontFamily: Style.font.family

  signal removeRequested()
  signal editRequested()
  signal saved(string text)
  signal cancelled()

  function startEdit() {
    root.editRequested()
  }

  implicitHeight: Math.max(editing ? editor.implicitHeight : topic.implicitHeight, actions.shown ? actions.height : 0) + Style.space(16)
  radius: Style.space(8)
  color: hover.hovered ? Util.alpha(Color.popups.text, 0.08) : Util.alpha(Color.popups.text, 0.05)

  Behavior on color { ColorAnimation { duration: Style.duration(150) } }

  HoverHandler {
    id: hover
  }

  Text {
    id: topic

    visible: !root.editing
    x: Style.space(10)
    width: parent.width - Style.space(20) - (actions.shown ? actions.width : 0)
    anchors.verticalCenter: parent.verticalCenter
    text: root.text
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Color.popups.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Loader {
    id: editor

    x: Style.space(6)
    width: parent.width - Style.space(12)
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

  HoverActions {
    id: actions

    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    shown: hover.hovered && !root.editing
    fontFamily: root.fontFamily
    onEditClicked: root.startEdit()
    onRemoveClicked: root.removeRequested()
  }
}
