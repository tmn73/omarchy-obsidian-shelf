import QtQuick
import "Model.js" as Model

// A ListModel kept in step with a list of items by their `key`.
//
// Replacing a JS array model rebuilds every delegate on each refresh, which
// kills running animations and the scroll position. Applying the keyed plan
// instead removes and inserts only what changed, so a ListView's add and
// remove transitions play for exactly the rows that came or went.
ListModel {
  id: root

  function keys() {
    var out = []
    for (var i = 0; i < count; i++)
      out.push(get(i).key)
    return out
  }

  function sync(items) {
    var next = Model.toArray(items) || []
    var byKey = {}
    next.forEach(function (item) { byKey[item.key] = item })
    var plan = Model.keyedSyncPlan(keys(), next.map(function (item) { return item.key }))
    plan.remove.forEach(function (index) { remove(index) })
    plan.insert.forEach(function (op) { insert(op.index, byKey[op.key]) })
    for (var i = 0; i < count; i++)
      set(i, byKey[get(i).key])
  }

  // Optimistic removal: the row leaves at once, and the next sync confirms it
  // or brings it back when the helper refused the action.
  function removeKey(key) {
    for (var i = 0; i < count; i++) {
      if (get(i).key === key) {
        remove(i)
        return true
      }
    }
    return false
  }

  // An edit keeps the row in place: swap its key and roles, so the next sync
  // finds the new key already there and plays no motion.
  function replaceKey(oldKey, item) {
    for (var i = 0; i < count; i++) {
      if (get(i).key === oldKey) {
        set(i, item)
        return true
      }
    }
    return false
  }
}
