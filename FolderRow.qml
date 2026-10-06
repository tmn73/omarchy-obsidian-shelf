import QtQuick
import qs.Commons
import "Model.js" as Model

// One saved link: platform glyph, title, domain and age, a two-line excerpt,
// then open, plus edit and remove on hover. A fresh row flashes in the accent
// color and wears a NEW tag while it is fresh.
Item {
  id: root

  property string title: ""
  property string excerpt: ""
  property string url: ""
  property string domain: ""
  property string modifiedAt: ""
  property bool fresh: false
  property bool current: false
  property string fontFamily: Style.font.family
  property bool editing: false

  signal openRequested()
  signal removeRequested()
  signal editRequested()
  signal saved(string text)
  signal cancelled()

  function startEdit() {
    root.editRequested()
  }

  readonly property string platformGlyph: {
    if (/(^|\.)(youtube\.com|youtu\.be|vimeo\.com|twitch\.tv)$/.test(domain))
      return ""
    if (/(^|\.)(x\.com|twitter\.com|bsky\.app|threads\.com|mastodon\.social)$/.test(domain))
      return ""
    return ""
  }

  implicitHeight: body.implicitHeight + Style.space(24)

  Component.onCompleted: if (fresh) flash.start()

  Rectangle {
    id: background

    anchors.fill: parent
    radius: Style.space(10)
    color: hover.hovered || root.current ? Util.alpha(Color.popups.text, 0.05) : "transparent"

    Behavior on color { ColorAnimation { duration: Style.duration(150) } }
  }

  Rectangle {
    id: flashLayer

    anchors.fill: parent
    radius: Style.space(10)
    color: "transparent"

    SequentialAnimation {
      id: flash

      ColorAnimation { target: flashLayer; property: "color"; to: Util.alpha(Color.accent, 0.18); duration: Style.duration(1) }
      PauseAnimation { duration: Style.duration(650) }
      ColorAnimation { target: flashLayer; property: "color"; to: Util.alpha(Color.accent, 0); duration: Style.duration(2600); easing.type: Easing.OutCubic }
    }
  }

  HoverHandler {
    id: hover
  }

  Row {
    id: body

    x: Style.space(12)
    y: Style.space(12)
    width: parent.width - Style.space(24)
    spacing: Style.space(12)

    Rectangle {
      width: Style.space(38)
      height: width
      radius: Style.space(9)
      color: Util.alpha(Color.popups.text, 0.08)

      Text {
        anchors.centerIn: parent
        text: root.platformGlyph
        textFormat: Text.PlainText
        color: Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }
    }

    Column {
      width: body.width - Style.space(38) - actions.width - body.spacing * 2
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Loader {
          active: root.editing
          visible: active
          width: parent.width
          sourceComponent: InlineEditor {
            initialText: root.title
            font.family: root.fontFamily
            onSaved: function (text) { root.saved(text) }
            onCancelled: root.cancelled()
          }
        }

        Text {
          id: titleText

          visible: !root.editing
          width: Math.min(implicitWidth, parent.width - (newTag.visible ? newTag.width + parent.spacing : 0))
          text: root.title
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Color.popups.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Rectangle {
          id: newTag

          visible: root.fresh && !root.editing
          anchors.verticalCenter: titleText.verticalCenter
          width: newLabel.implicitWidth + Style.space(10)
          height: newLabel.implicitHeight + Style.space(2)
          radius: Style.space(4)
          color: Color.accent

          Text {
            id: newLabel

            anchors.centerIn: parent
            text: "NEW"
            textFormat: Text.PlainText
            color: Color.popups.background
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      Text {
        width: parent.width
        visible: root.excerpt !== ""
        text: root.excerpt
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        lineHeight: 1.15
        color: Util.alpha(Color.popups.text, 0.85)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: age

        text: (root.domain !== "" ? root.domain + "  ·  " : "") + Model.relativeAge(root.modifiedAt, Date.now())
        textFormat: Text.PlainText
        color: Util.alpha(Color.popups.text, 0.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Column {
      id: actions

      spacing: Style.space(4)

      RowButton {
        anchors.right: parent.right
        visible: root.url !== ""
        glyph: "\uf08e"
        label: qsTr("Open in browser")
        fontFamily: root.fontFamily
        onClicked: root.openRequested()
      }

      HoverActions {
        shown: hover.hovered || root.current
        fontFamily: root.fontFamily
        onEditClicked: root.startEdit()
        onRemoveClicked: root.removeRequested()
      }
    }
  }
}
