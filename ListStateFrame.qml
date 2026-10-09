import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// What every list component shares: the contract ShelfPopup binds to, the
// pane fade on a tab change, and the states shown instead of rows (empty,
// missing file, unreadable file).
Item {
  id: root

  property var service: null
  property var listConfig: null
  property var listPayload: null
  property string fontFamily: Style.font.family
  property real contentHeightHint: stateHeight
  property bool showRows: false
  property string emptyTitle: ""
  property string emptyText: ""
  property string editingKey: ""
  property int openCount: 0
  readonly property bool editing: editingKey !== ""

  signal settingsRequested()
  signal createRequested()

  readonly property string listState: listPayload ? String(listPayload.state || "") : ""
  readonly property real stateHeight: stateBlock.implicitHeight + Style.space(56)

  function moveHighlight(dy) {}
  function activateCurrent() {}
  function doneCurrent() {}
  function editCurrent() {}
  function removeCurrent() {}

  // The key a line gets after an edit: the same prefix, the new text.
  function editedKey(key, oldText, newText) {
    return key.slice(0, key.length - oldText.length) + newText
  }

  Component.onCompleted: paneIn.start()

  transform: Translate { id: paneShift }

  ParallelAnimation {
    id: paneIn

    NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Style.duration(320); easing.type: Easing.OutCubic }
    NumberAnimation { target: paneShift; property: "y"; from: Style.space(6); to: 0; duration: Style.duration(320); easing.type: Easing.OutCubic }
  }

  Column {
    id: stateBlock

    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(48), Style.space(300))
    spacing: Style.space(10)
    visible: !root.showRows

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.listState === "ok"
      text: ""
      textFormat: Text.PlainText
      color: Commons.Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.displayLarge
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.listState === "ok" ? root.emptyTitle : (root.listState === "" ? qsTr("Reading the vault") : (root.listPayload.message || qsTr("This list cannot be read")))
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.listState === "ok" || root.listState === "" ? Commons.Color.popups.text : Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8)

      Button {
        visible: root.listState === "missing"
        text: qsTr("Create it again")
        bordered: true
        background: Commons.Color.accent
        foreground: Commons.Color.popups.background
        onClicked: root.createRequested()
      }

      Button {
        visible: root.listState === "missing" || root.listState === "error"
        text: qsTr("Open settings")
        onClicked: root.settingsRequested()
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      visible: root.listState === "ok" && root.emptyText !== ""
      text: root.emptyText
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Util.alpha(Commons.Color.popups.text, 0.65)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
