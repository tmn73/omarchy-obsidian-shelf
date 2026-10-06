import QtQuick
import QtQuick.Controls
import qs.Commons

// The list view every row-based list shares: a keyed model, so only rows that
// came or went animate, and the motion of spec 8.3.
//
// The first fill after creation runs with transitions off: switching tabs
// should feel like one pane fading in, not every row arriving at once.
ListView {
  id: root

  property alias keyedModel: keyed
  property bool ready: false

  function syncItems(items) {
    keyed.sync(items)
    if (!ready)
      Qt.callLater(function () { root.ready = true })
  }

  model: KeyedListModel { id: keyed }
  clip: true
  spacing: Style.space(2)
  currentIndex: -1
  boundsBehavior: Flickable.StopAtBounds
  interactive: contentHeight > height
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

  add: Transition {
    id: addTransition

    enabled: root.ready

    ParallelAnimation {
      NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Style.duration(450); easing.type: Easing.OutCubic }
      NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Style.duration(700); easing.type: Easing.OutBack; easing.overshoot: 1.6 }
      NumberAnimation { property: "y"; from: addTransition.ViewTransition.destination.y - Style.space(16); duration: Style.duration(700); easing.type: Easing.OutBack; easing.overshoot: 1.6 }
    }
  }

  remove: Transition {
    ParallelAnimation {
      NumberAnimation { property: "x"; to: Style.space(48); duration: Style.duration(240); easing.type: Easing.InCubic }
      NumberAnimation { property: "opacity"; to: 0; duration: Style.duration(240); easing.type: Easing.InCubic }
    }
  }

  displaced: Transition {
    NumberAnimation { properties: "x,y"; duration: Style.duration(400); easing.type: Easing.OutCubic }
  }
}
