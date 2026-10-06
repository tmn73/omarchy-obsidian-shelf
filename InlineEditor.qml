import QtQuick
import qs.Commons
import qs.Ui

// The field a row shows while you edit its text. Enter saves, Escape cancels,
// and losing focus saves too, so a click elsewhere never throws an edit away.
TextField {
  id: root

  property string initialText: ""
  property bool closed: false

  signal saved(string text)
  signal cancelled()

  font.pixelSize: Style.font.body

  Component.onCompleted: {
    text = initialText
    forceActiveFocus()
    selectAll()
  }

  function finish(save) {
    if (closed)
      return
    closed = true
    var value = text.trim()
    if (save && value !== "" && value !== initialText)
      root.saved(value)
    else
      root.cancelled()
  }

  onAccepted: finish(true)
  onActiveFocusChanged: if (!activeFocus) finish(true)
  Keys.onEscapePressed: finish(false)
}
