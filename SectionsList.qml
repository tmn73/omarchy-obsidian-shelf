import QtQuick
import qs.Commons
import "Model.js" as Model

// The `sections` list: one column per heading, then the two-step clear.
// Each column is its own keyed list, so new topics arrive and a clear sweeps
// every topic out with the same motion as the other lists.
ListStateFrame {
  id: root

  readonly property var sections: listPayload && listPayload.state === "ok" ? (Model.toArray(listPayload.sections) || []) : []
  readonly property int total: Model.listItemCount(listPayload)
  readonly property int columnCount: Math.max(1, Math.min(sections.length, 3))
  readonly property real gap: Style.space(12)
  // The first column takes the accent, the second the urgent color: with the
  // default Good and Bad headings that reads as good and bad without words.
  readonly property var dotColors: [Color.accent, Color.urgent]

  contentHeightHint: showRows ? body.implicitHeight : stateHeight
  showRows: sections.length > 0
  emptyTitle: qsTr("No sections")
  emptyText: qsTr("Add a heading such as ## Good to the file.")

  // Topics have no per-row action in this version (spec section 2), so the
  // keyboard contract has nothing to move to or finish here.
  function moveHighlight(dy) {}
  function activateCurrent() {}
  function doneCurrent() {}
  function editCurrent() {}
  function removeCurrent() {}

  function removeTopic(column, key) {
    if (!service || !listConfig)
      return
    column.removeKey(key)
    service.act("remove", listConfig.id, { item: key })
  }

  function saveTopic(column, key, oldText, text) {
    editingKey = ""
    column.replaceKey(key, { key: editedKey(key, oldText, text), text: text })
    service.act("edit", listConfig.id, { item: key, text: text })
  }

  function clearAll() {
    if (!service || !listConfig)
      return
    for (var i = 0; i < columns.count; i++)
      columns.itemAt(i).sweep()
    service.act("clear", listConfig.id, {})
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
      spacing: Style.space(12)

      Grid {
        width: parent.width
        columns: root.columnCount
        columnSpacing: root.gap
        rowSpacing: root.gap

        Repeater {
          id: columns

          model: root.sections

          delegate: Column {
            id: column

            required property var modelData
            required property int index
            readonly property var items: Model.toArray(modelData.items) || []

            function sweep() {
              view.syncItems([])
            }

            function removeKey(key) {
              view.keyedModel.removeKey(key)
            }

            function replaceKey(key, item) {
              view.keyedModel.replaceKey(key, item)
            }

            width: (body.width - root.gap * (root.columnCount - 1)) / root.columnCount
            spacing: Style.space(8)

            onItemsChanged: view.syncItems(items)
            Component.onCompleted: view.syncItems(items)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(8)
                height: width
                radius: Style.space(2)
                color: column.index < root.dotColors.length ? root.dotColors[column.index] : Util.alpha(Color.popups.text, 0.4)
              }

              Text {
                width: parent.width - Style.space(40)
                text: column.modelData.heading.toUpperCase()
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Color.popups.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: Style.space(1.5)
              }

              Text {
                text: String(view.count)
                textFormat: Text.PlainText
                color: Util.alpha(Color.popups.text, 0.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            ShelfListView {
              id: view

              width: parent.width
              height: contentHeight
              interactive: false
              spacing: Style.space(8)

              delegate: TopicCard {
                required property string key
                required text

                width: view.width
                fontFamily: root.fontFamily
                editing: root.editingKey === key
                onRemoveRequested: root.removeTopic(column, key)
                onEditRequested: root.editingKey = key
                onSaved: function (newText) { root.saveTopic(column, key, text, newText) }
                onCancelled: root.editingKey = ""
              }
            }

            DashedBox {
              width: parent.width
              visible: view.count === 0
              text: qsTr("Nothing yet")
              fontFamily: root.fontFamily
            }
          }
        }
      }

      ClearButton {
        width: parent.width
        count: root.total
        listName: root.listConfig ? root.listConfig.name : ""
        fontFamily: root.fontFamily
        onConfirmed: root.clearAll()
      }
    }
  }
}
