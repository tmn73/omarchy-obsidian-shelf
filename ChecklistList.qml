import QtQuick
import qs.Commons
import "Model.js" as Model

// The `checklist` list: open todos in file order. Ticking removes the row
// first, then asks the helper.
ListStateFrame {
  id: root

  readonly property var items: listPayload && listPayload.state === "ok" ? (Model.toArray(listPayload.items) || []) : []

  contentHeightHint: showRows ? view.contentHeight : stateHeight
  showRows: items.length > 0
  emptyTitle: qsTr("Nothing left.")
  emptyText: ""

  onItemsChanged: view.syncItems(items)
  Component.onCompleted: view.syncItems(items)

  function moveHighlight(dy) {
    if (view.count > 0)
      view.currentIndex = Math.max(0, Math.min(view.count - 1, view.currentIndex + dy))
  }

  function activateCurrent() {
    doneCurrent()
  }

  function doneCurrent() {
    if (view.currentItem && view.currentItem.tick)
      view.currentItem.tick()
  }

  function finishTick(key) {
    if (!service || !listConfig)
      return
    view.keyedModel.removeKey(key)
    service.act("done", listConfig.id, { item: key })
  }

  ShelfListView {
    id: view

    anchors.fill: parent
    visible: root.showRows

    delegate: ChecklistRow {
      required property int index
      required property string key
      required text

      width: view.width
      current: index === view.currentIndex
      fontFamily: root.fontFamily
      onTickRequested: root.finishTick(key)
    }
  }
}
