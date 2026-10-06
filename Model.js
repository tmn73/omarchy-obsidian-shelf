// Pure logic for Obsidian Shelf: settings, counts, fresh items and keyed sync.
//
// Everything here is Qt-free so it runs under node (tests/model.test.js). The
// helper owns the vault, the QML owns rendering and scheduling; this file owns
// what the settings and the payload mean.

var TYPES = ['folder', 'checklist', 'sections']
var ID_RE = /^[a-z0-9-]{1,32}$/
var KEY_SEPARATOR = '\u0000'

var DEFAULT_LISTS = [
  { id: 'read-later', name: 'Read later', type: 'folder', path: 'Read Later', badge: true, onDone: 'delete' },
  { id: 'retro', name: 'Retro', type: 'sections', path: 'Retrospective.md', badge: false, onDone: 'delete' },
  { id: 'todo', name: 'Todo', type: 'checklist', path: 'Todo.md', badge: true, onDone: 'delete' }
]

// Arrays that come from shell.json fail Array.isArray and have no indexOf, and
// a value typed into a settings field arrives as a string. Copy into a plain
// array at the boundary so nothing below has to care.
function toArray (value) {
  if (value === undefined || value === null) return null
  if (typeof value === 'string') {
    try { value = JSON.parse(value) } catch (e) { return null }
  }
  if (typeof value !== 'object' || typeof value.length !== 'number') return null
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function text (value) {
  return typeof value === 'string' ? value.trim() : ''
}

function normalizeList (entry, position, seen, errors) {
  var label = 'List ' + position
  var id = text(entry && entry.id)
  if (!ID_RE.test(id)) { errors.push(label + ' has no valid id'); return null }
  if (seen[id]) { errors.push(label + ' repeats the id ' + id); return null }
  var type = text(entry.type)
  if (TYPES.indexOf(type) < 0) { errors.push(label + ' has no valid type'); return null }
  var name = text(entry.name)
  if (name === '' || name.length > 24) { errors.push(label + ' has no valid name'); return null }
  var path = text(entry.path)
  if (path === '') { errors.push(label + ' has no path'); return null }
  seen[id] = true
  return {
    id: id,
    name: name,
    type: type,
    path: path,
    badge: typeof entry.badge === 'boolean' ? entry.badge : type !== 'sections',
    onDone: entry.onDone === 'check' ? 'check' : 'delete'
  }
}

function normalizeSettings (raw) {
  raw = raw || {}
  var errors = []
  var interval = Math.round(Number(raw.refreshIntervalSec))
  if (!isFinite(interval) || raw.refreshIntervalSec === "" || raw.refreshIntervalSec === undefined) interval = 10
  interval = Math.min(600, Math.max(10, interval))

  var lists = []
  var given = raw.lists === undefined || raw.lists === null ? null : toArray(raw.lists)
  if (raw.lists === undefined || raw.lists === null) {
    lists = DEFAULT_LISTS.map(function (l) { return Object.assign({}, l) })
  } else if (given === null) {
    errors.push('The lists setting is not a JSON array')
  } else {
    var seen = {}
    for (var i = 0; i < given.length; i++) {
      var list = normalizeList(given[i], i + 1, seen, errors)
      if (list) lists.push(list)
    }
  }

  return {
    vaultPath: text(raw.vaultPath),
    refreshIntervalSec: interval,
    syncCheckCommand: text(raw.syncCheckCommand),
    obsidianSync: raw.obsidianSync !== false && raw.obsidianSync !== 'false',
    tweetPreviews: raw.tweetPreviews === true || raw.tweetPreviews === 'true',
    lists: lists,
    errors: errors
  }
}

function findList (payload, id) {
  var lists = payload && toArray(payload.lists)
  if (!lists) return null
  for (var i = 0; i < lists.length; i++) if (lists[i] && lists[i].id === id) return lists[i]
  return null
}

function listItemCount (listPayload) {
  if (!listPayload || listPayload.state !== 'ok') return 0
  var sections = toArray(listPayload.sections)
  if (sections) {
    var total = 0
    for (var i = 0; i < sections.length; i++) total += (toArray(sections[i].items) || []).length
    return total
  }
  return (toArray(listPayload.items) || []).length
}

function badgeCount (payload, lists) {
  var total = 0
  ;(toArray(lists) || []).forEach(function (cfg) {
    if (cfg.badge) total += listItemCount(findList(payload, cfg.id))
  })
  return total
}

function itemKeys (payload) {
  var keys = []
  ;(toArray(payload && payload.lists) || []).forEach(function (list) {
    var sections = toArray(list.sections)
    var groups = sections ? sections.map(function (s) { return toArray(s.items) || [] }) : [toArray(list.items) || []]
    groups.forEach(function (items) {
      items.forEach(function (item) { keys.push(list.id + KEY_SEPARATOR + item.key) })
    })
  })
  return keys
}

function freshKeys (previousPayload, nextPayload) {
  if (!previousPayload) return []
  var before = {}
  itemKeys(previousPayload).forEach(function (k) { before[k] = true })
  return itemKeys(nextPayload).filter(function (k) { return !before[k] })
}

// Whether a folder item still waits for its tweet preview. The helper marks
// an item pending only until a fetch succeeded or failed, so asking for the
// previews again never loops.
function previewsPending (payload) {
  return (toArray(payload && payload.lists) || []).some(function (list) {
    return (toArray(list.items) || []).some(function (item) { return item.previewPending === true })
  })
}

// Unseen items: what arrived since the popup was last opened. Keys that left
// the vault drop out, new arrivals join, nothing repeats.
function mergeUnseen (unseen, added, payload) {
  var present = {}
  itemKeys(payload).forEach(function (k) { present[k] = true })
  var out = []
  var seen = {}
  ;(toArray(unseen) || []).concat(toArray(added) || []).forEach(function (k) {
    if (present[k] && !seen[k]) {
      seen[k] = true
      out.push(k)
    }
  })
  return out
}

// How many fresh keys belong to a list that counts in the bar badge. The chip
// pings for these only: a retro topic arriving is not worth a ping.
function freshInBadgeLists (fresh, lists) {
  var badgeIds = {}
  ;(toArray(lists) || []).forEach(function (cfg) { if (cfg.badge) badgeIds[cfg.id] = true })
  return (toArray(fresh) || []).filter(function (k) {
    return badgeIds[String(k).split(KEY_SEPARATOR)[0]]
  }).length
}

function relativeAge (iso, nowMs) {
  var seconds = Math.floor((nowMs - Date.parse(iso)) / 1000)
  if (!isFinite(seconds) || seconds < 60) return 'now'
  if (seconds < 3600) return Math.floor(seconds / 60) + 'm'
  if (seconds < 86400) return Math.floor(seconds / 3600) + 'h'
  return Math.floor(seconds / 86400) + 'd'
}

function pad2 (n) {
  return (n < 10 ? '0' : '') + n
}

function clockText (iso) {
  if (!iso) return ''
  var date = new Date(iso)
  if (isNaN(date.getTime())) return ''
  return pad2(date.getHours()) + ':' + pad2(date.getMinutes())
}

function tooltipText (payload, lists) {
  var parts = []
  ;(toArray(lists) || []).forEach(function (cfg) {
    if (!cfg.badge) return
    var count = listItemCount(findList(payload, cfg.id))
    if (count > 0) parts.push(count + ' ' + cfg.name.toLowerCase())
  })
  return parts.length ? parts.join(', ') : 'Nothing on the shelf'
}

// The edits that turn currentKeys into nextKeys: removals (descending indices,
// so each splice leaves the next index valid), then insertions in ascending
// order. Kept rows are never moved, so their delegates and animations survive.
// When kept keys change order, which a refresh never does on its own, the plan
// replaces everything.
function keyedSyncPlan (currentKeys, nextKeys) {
  var current = toArray(currentKeys) || []
  var next = toArray(nextKeys) || []
  var inNext = {}
  var inCurrent = {}
  next.forEach(function (k) { inNext[k] = true })
  current.forEach(function (k) { inCurrent[k] = true })

  var kept = current.filter(function (k) { return inNext[k] })
  var nextKept = next.filter(function (k) { return inCurrent[k] })
  if (kept.join(KEY_SEPARATOR) !== nextKept.join(KEY_SEPARATOR)) {
    return {
      remove: current.map(function (k, i) { return i }).reverse(),
      insert: next.map(function (k, i) { return { index: i, key: k } })
    }
  }

  var remove = []
  for (var i = current.length - 1; i >= 0; i--) if (!inNext[current[i]]) remove.push(i)
  var insert = []
  next.forEach(function (k, index) { if (!inCurrent[k]) insert.push({ index: index, key: k }) })
  return { remove: remove, insert: insert }
}

// The Obsidian Sync setup step for a helper sync state, or null when there is
// nothing to do (running) or nothing known yet.
var SYNC_STEPS = {
  'no-client': { title: 'Install the sync client', text: 'Obsidian Headless keeps this vault in sync while the Obsidian app is closed.', button: 'Install Obsidian Headless' },
  'logged-out': { title: 'Log in to Obsidian Sync', text: 'A terminal opens. Type your Obsidian email, password and 2FA code there. The plugin never sees them.', button: 'Log in' },
  unlinked: { title: 'Link this vault', text: 'A terminal lists your remote vaults. Type the name of the one to sync into this folder.', button: 'Link this vault' },
  stopped: { title: 'Start the background sync', text: 'A user service runs the sync now and at every login.', button: 'Start background sync' }
}

function syncStep (state) {
  return SYNC_STEPS[state] || null
}

if (typeof module !== 'undefined') {
  module.exports = {
    DEFAULT_LISTS: DEFAULT_LISTS,
    KEY_SEPARATOR: KEY_SEPARATOR,
    toArray: toArray,
    normalizeSettings: normalizeSettings,
    findList: findList,
    listItemCount: listItemCount,
    badgeCount: badgeCount,
    itemKeys: itemKeys,
    freshKeys: freshKeys,
    freshInBadgeLists: freshInBadgeLists,
    mergeUnseen: mergeUnseen,
    previewsPending: previewsPending,
    relativeAge: relativeAge,
    clockText: clockText,
    tooltipText: tooltipText,
    keyedSyncPlan: keyedSyncPlan,
    syncStep: syncStep
  }
}
