import QtQuick
import qs.Commons
import qs.Ui

// The reminder settings, shown when a board is on the shelf: the time of the
// morning summary, and whether a reminder plays a sound. The sound is one of
// the sounds already on the system; the plugin ships none.
Column {
  id: root

  property var config: ({})
  property string fontFamily: Style.font.family
  property var sounds: []
  property string defaultSound: ""

  signal settingChanged(string name, var value)

  readonly property string soundValue: config.reminderSoundFile || defaultSound
  readonly property var soundOptions: sounds.map(function (s) {
    return { value: s.path, label: s.name.replace(/[-_]/g, " ") + (s.theme !== "freedesktop" ? " · " + s.theme : "") }
  })

  spacing: Style.space(10)

  function playSound(path) {
    if (path !== "")
      helper.run(["play-sound", "--path", path], function () {})
  }

  Component.onCompleted: helper.run(["sounds"], function (data) {
    root.sounds = data.sounds || []
    root.defaultSound = data["default"] || ""
  })

  HelperCall { id: helper }

  SettingsCaption { text: qsTr("REMINDERS"); fontFamily: root.fontFamily }

  Row {
    spacing: Style.space(10)

    SettingsCaption { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Morning summary at"); fontFamily: root.fontFamily }

    TextField {
      width: Style.space(90)
      text: root.config.reminderTime || "09:00"
      placeholderText: "09:00"
      font.family: root.fontFamily
      onEditingFinished: {
        var value = text.trim()
        if (/^([01]\d|2[0-3]):[0-5]\d$/.test(value) && value !== root.config.reminderTime)
          root.settingChanged("reminderTime", value)
      }
    }
  }

  Toggle {
    width: parent.width
    label: qsTr("Play a sound")
    description: root.sounds.length > 0
      ? qsTr("When a card is due, and with the morning summary.")
      : qsTr("No sound theme on this system. Install sound-theme-freedesktop to get one.")
    checked: root.config.reminderSound !== false
    fontFamily: root.fontFamily
    onClicked: root.settingChanged("reminderSound", !checked)
  }

  Row {
    visible: root.config.reminderSound !== false && root.sounds.length > 0
    spacing: Style.space(8)

    Dropdown {
      width: Style.space(260)
      showLabel: false
      options: root.soundOptions
      value: root.soundValue
      fontFamily: root.fontFamily
      onChanged: function (value) {
        root.settingChanged("reminderSoundFile", value)
        root.playSound(value)
      }
    }

    RowButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: ""
      label: qsTr("Play the sound")
      fontFamily: root.fontFamily
      onClicked: root.playSound(root.soundValue)
    }
  }

  Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.popups.text, 0.08) }
}
