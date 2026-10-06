import QtQuick
import qs.Commons
import "Model.js" as Model

// The `folder` list: one row per saved note, newest first.
ListStateFrame {
  id: root

  readonly property var items: listPayload && listPayload.state === "ok" ? (Model.toArray(listPayload.items) || []) : []

  contentHeightHint: showRows ? view.contentHeight : stateHeight
  showRows: items.length > 0
  emptyTitle: qsTr("All caught up")
  emptyText: qsTr("Share a link to Obsidian from your phone. It lands here.")

  onItemsChanged: view.syncItems(items)
  Component.onCompleted: view.syncItems(items)

  function currentItem() {
    return view.currentIndex >= 0 && view.currentIndex < view.count ? view.keyedModel.get(view.currentIndex) : null
  }

  function moveHighlight(dy) {
    if (view.count > 0)
      view.currentIndex = Math.max(0, Math.min(view.count - 1, view.currentIndex + dy))
  }

  function activateCurrent() {
    var item = currentItem()
    if (item && service)
      service.openUrl(item.url)
  }

  function doneCurrent() {
    removeCurrent()
  }

  function removeCurrent() {
    var item = currentItem()
    if (item)
      removeNote(item.key)
  }

  function editCurrent() {
    if (view.currentItem && view.currentItem.startEdit)
      view.currentItem.startEdit()
  }

  function removeNote(key) {
    if (!service || !listConfig)
      return
    view.keyedModel.removeKey(key)
    service.act("remove", listConfig.id, { item: key })
  }

  function saveTitle(key, text) {
    editingKey = ""
    for (var i = 0; i < view.count; i++) {
      if (view.keyedModel.get(i).key === key)
        view.keyedModel.setProperty(i, "title", text)
    }
    service.act("edit", listConfig.id, { item: key, text: text })
  }

  ShelfListView {
    id: view

    anchors.fill: parent
    spacing: Style.space(6)
    visible: root.showRows

    delegate: FolderRow {
      required property int index
      required property string key
      required title
      required excerpt
      required url
      required domain
      required image
      required avatar
      required modifiedAt

      width: view.width
      current: index === view.currentIndex
      fresh: root.service ? root.service.unseen.indexOf(root.listConfig.id + Model.KEY_SEPARATOR + key) >= 0 : false
      replay: root.openCount
      fontFamily: root.fontFamily
      editing: root.editingKey === key
      onOpenRequested: root.service.openUrl(url)
      onRemoveRequested: root.removeNote(key)
      onEditRequested: root.editingKey = key
      onSaved: function (text) { root.saveTitle(key, text) }
      onCancelled: root.editingKey = ""
    }
  }
}
