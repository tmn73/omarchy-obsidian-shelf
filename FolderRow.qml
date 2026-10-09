import QtQuick
import qs.Commons
import qs.Commons as Commons
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
  property string image: ""
  property string avatar: ""
  property string modifiedAt: ""
  property bool fresh: false
  property bool current: false
  property string fontFamily: Style.font.family
  property bool editing: false
  property int replay: 0

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
    if (/(^|\.)reddit\.com$/.test(domain))
      return "\uf1a1"
    if (/(^|\.)instagram\.com$/.test(domain))
      return "\uf16d"
    return ""
  }

  implicitHeight: body.implicitHeight + Style.space(24)

  Component.onCompleted: if (fresh) flash.start()
  onReplayChanged: if (fresh) flash.restart()

  Rectangle {
    id: background

    anchors.fill: parent
    radius: Style.space(10)
    // Every row sits on its own faint card, like the board cards, so the
    // rows read apart without lines.
    color: hover.hovered || root.current ? Util.alpha(Commons.Color.popups.text, 0.07) : Util.alpha(Commons.Color.popups.text, 0.03)

    Behavior on color { ColorAnimation { duration: Style.duration(150) } }
  }

  Rectangle {
    id: flashLayer

    anchors.fill: parent
    radius: Style.space(10)
    color: "transparent"

    SequentialAnimation {
      id: flash

      ColorAnimation { target: flashLayer; property: "color"; to: Util.alpha(Commons.Color.accent, 0.18); duration: Style.duration(1) }
      PauseAnimation { duration: Style.duration(650) }
      ColorAnimation { target: flashLayer; property: "color"; to: Util.alpha(Commons.Color.accent, 0); duration: Style.duration(2600); easing.type: Easing.OutCubic }
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

    Thumbnail {
      id: thumb

      width: root.image !== "" ? Style.space(112) : Style.space(38)
      height: root.image !== "" ? Style.space(63) : Style.space(38)
      source: root.image !== "" ? root.image : root.avatar
      round: root.image === "" && root.avatar !== ""
      glyph: root.platformGlyph
      video: root.platformGlyph === "\uf04b"
      fontFamily: root.fontFamily
    }

    Column {
      width: body.width - thumb.width - actions.width - body.spacing * 2
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

        Thumbnail {
          id: miniAvatar

          visible: root.image !== "" && root.avatar !== "" && !root.editing
          anchors.verticalCenter: titleText.verticalCenter
          width: Style.space(18)
          height: width
          round: true
          source: visible ? root.avatar : ""
          fontFamily: root.fontFamily
        }

        // The natural width of the title. A Text that elides reports the
        // elided width as its implicitWidth, so binding to it shrinks the
        // title a little more on each layout.
        TextMetrics {
          id: titleMetrics

          font: titleText.font
          text: root.title
        }

        Text {
          id: titleText

          visible: !root.editing
          width: Math.min(Math.ceil(titleMetrics.advanceWidth) + 1, parent.width - (newTag.visible ? newTag.width + parent.spacing : 0) - (miniAvatar.visible ? miniAvatar.width + parent.spacing : 0))
          text: root.title
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          maximumLineCount: root.excerpt === "" ? 2 : 1
          elide: Text.ElideRight
          color: Commons.Color.popups.text
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
          color: Commons.Color.accent

          Text {
            id: newLabel

            anchors.centerIn: parent
            text: "NEW"
            textFormat: Text.PlainText
            color: Commons.Color.popups.background
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
        color: Util.alpha(Commons.Color.popups.text, 0.85)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: age

        text: (root.domain !== "" ? root.domain + "  ·  " : "") + Model.relativeAge(root.modifiedAt, Date.now())
        textFormat: Text.PlainText
        color: Util.alpha(Commons.Color.popups.text, 0.6)
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
