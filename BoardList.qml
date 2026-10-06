import QtQuick
import qs.Commons
import "Board.js" as Board

// The `board` list: the lanes of an Obsidian Kanban board, stacked. The lane
// closest to Done comes first, the Complete lanes come last and fold. Every
// action goes to the helper; the next read shows the result.
ListStateFrame {
  id: root

  readonly property var lanes: listPayload && listPayload.state === "ok" ? Board.boardView(listPayload) : []
  readonly property bool datesOn: listPayload ? listPayload.datesOn !== false : true
  property string today: Board.isoDay(new Date())
  property bool doneOpen: false
  property string currentKey: ""
  property string datingKey: ""
  property string statusKey: ""
  // The date and status panels take the keys: the popup keys stay off.
  readonly property bool typing: datingKey !== "" || statusKey !== ""
  // The cards the keyboard walks through, in the order they show.
  readonly property var visibleKeys: {
    var keys = []
    lanes.forEach(function (lane) {
      if (!lane.complete || doneOpen)
        lane.items.forEach(function (card) { keys.push(card.key) })
    })
    return keys
  }

  // The Repeater follows the lane names, not the lanes: each read gives new
  // lane objects, and a new model would rebuild every card, open editors too.
  property var laneKeys: []

  function laneKey(lane) {
    return (lane.complete ? "done\n" : "open\n") + lane.title
  }

  function syncLaneKeys() {
    var keys = lanes.map(laneKey)
    if (JSON.stringify(keys) !== JSON.stringify(laneKeys))
      laneKeys = keys
  }

  function laneFor(key) {
    for (var i = 0; i < lanes.length; i++)
      if (laneKey(lanes[i]) === key)
        return lanes[i]
    return { title: "", complete: false, items: [] }
  }

  onLanesChanged: syncLaneKeys()
  Component.onCompleted: syncLaneKeys()

  contentHeightHint: showRows ? body.implicitHeight : stateHeight
  showRows: lanes.length > 0
  emptyTitle: qsTr("No lanes")
  emptyText: qsTr("Add a heading such as ## To do to the file.")

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.today = Board.isoDay(new Date())
  }

  function act(action, args) {
    if (service && listConfig)
      service.act(action, listConfig.id, args)
  }

  function laneOf(key) {
    for (var i = 0; i < lanes.length; i++)
      for (var j = 0; j < lanes[i].items.length; j++)
        if (lanes[i].items[j].key === key)
          return lanes[i].title
    return ""
  }

  function moveHighlight(dy) {
    if (visibleKeys.length === 0)
      return
    var index = visibleKeys.indexOf(currentKey)
    currentKey = visibleKeys[Math.max(0, Math.min(visibleKeys.length - 1, index < 0 ? 0 : index + dy))]
  }

  function activateCurrent() { doneCurrent() }
  function doneCurrent() { if (currentKey !== "") tick(currentKey) }
  function editCurrent() { if (currentKey !== "") editingKey = currentKey }
  function removeCurrent() { if (currentKey !== "") remove(currentKey) }
  function moveCard(step) { if (currentKey !== "") shift(currentKey, step) }
  function dateCurrent() { if (currentKey !== "" && datesOn) toggleDate(currentKey) }
  function statusCurrent() { if (currentKey !== "") toggleStatus(currentKey) }

  function tick(key) { act("done", { item: key }) }
  function remove(key) { act("remove", { item: key }) }
  function clearDone() { act("clear", {}) }
  function toggleDate(key) { statusKey = ""; datingKey = datingKey === key ? "" : key }
  function toggleStatus(key) { datingKey = ""; statusKey = statusKey === key ? "" : key }

  function moveTo(key, lane) {
    statusKey = ""
    if (lane !== laneOf(key))
      act("move", { item: key, lane: lane })
  }

  // A new status is a new lane; the card moves there right after.
  function addLaneAndMove(key, title) {
    statusKey = ""
    act("lane", { title: title })
    act("move", { item: key, lane: title })
  }

  function shift(key, step) {
    var lane = Board.neighbour(listPayload, laneOf(key), step)
    if (lane !== "")
      act("move", { item: key, lane: lane })
  }

  function save(key, text) {
    editingKey = ""
    act("edit", { item: key, text: text })
  }

  function setDate(key, date, time) {
    datingKey = ""
    act("date", { item: key, date: date, time: time })
  }

  Flickable {
    anchors.fill: parent
    visible: root.showRows
    contentHeight: body.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: body

      width: parent.width
      spacing: Style.space(14)

      Repeater {
        model: root.laneKeys

        delegate: BoardLane {
          required property string modelData
          required property int index

          width: body.width
          lane: root.laneFor(modelData)
          board: root
          accent: index === 0 && !lane.complete
          folded: lane.complete && !root.doneOpen
          fontFamily: root.fontFamily
        }
      }
    }
  }
}
