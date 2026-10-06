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

  function editCurrent() {
    if (view.currentItem && view.currentItem.startEdit)
      view.currentItem.startEdit()
  }

  function removeCurrent() {
    if (view.currentIndex >= 0 && view.currentIndex < view.count)
      removeLine(view.keyedModel.get(view.currentIndex).key, "remove")
  }

  function finishTick(key) {
    removeLine(key, "done")
  }

  function removeLine(key, action) {
    if (!service || !listConfig)
      return
    view.keyedModel.removeKey(key)
    service.act(action, listConfig.id, { item: key })
  }

  function saveText(key, oldText, text) {
    editingKey = ""
    view.keyedModel.replaceKey(key, { key: editedKey(key, oldText, text), text: text })
    service.act("edit", listConfig.id, { item: key, text: text })
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
      editing: root.editingKey === key
      onTickRequested: root.finishTick(key)
      onRemoveRequested: root.removeLine(key, "remove")
      onEditRequested: root.editingKey = key
      onSaved: function (newText) { root.saveText(key, text, newText) }
      onCancelled: root.editingKey = ""
    }
  }
}
