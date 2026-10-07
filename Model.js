// Pure logic for Obsidian Shelf: settings, counts, fresh items and keyed sync.
//
// Everything here is Qt-free so it runs under node (tests/model.test.js). The
// helper owns the vault, the QML owns rendering and scheduling; this file owns
// what the settings and the payload mean.

var TYPES = ['folder', 'checklist', 'sections', 'board']
var ID_RE = /^[a-z0-9-]{1,32}$/
var KEY_SEPARATOR = '\u0000'


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
  var out = {
    id: id,
    name: name,
    type: type,
    path: path,
    badge: typeof entry.badge === 'boolean' ? entry.badge : type !== 'sections',
    onDone: entry.onDone === 'check' ? 'check' : 'delete'
  }
  if (type === 'board') out.remind = entry.remind !== false && entry.remind !== 'false'
  return out
}

function normalizeSettings (raw) {
  raw = raw || {}
  var errors = []
  var interval = Math.round(Number(raw.refreshIntervalSec))
  if (!isFinite(interval) || raw.refreshIntervalSec === "" || raw.refreshIntervalSec === undefined) interval = 10
  interval = Math.min(600, Math.max(10, interval))

  var lists = []
  var given = raw.lists === undefined || raw.lists === null ? null : toArray(raw.lists)
  // A new user starts with an empty shelf: lists are added from the vault,
  // never assumed, because no two vaults share their paths.
  if (raw.lists === undefined || raw.lists === null) {
    lists = []
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
    linkPreviews: raw.linkPreviews !== false && raw.linkPreviews !== 'false',
    reminderTime: /^([01]\d|2[0-3]):[0-5]\d$/.test(text(raw.reminderTime)) ? text(raw.reminderTime) : '09:00',
    reminderSound: raw.reminderSound !== false && raw.reminderSound !== 'false',
    reminderSoundFile: text(raw.reminderSoundFile),
    lists: lists,
    errors: errors
  }
}

// Where a new line can go: the headings of a notes list, the open lanes of
// a board, nothing for the other kinds.
function addTargets (cfg, listPayload) {
  if (!cfg || !listPayload) return []
  if (cfg.type === 'sections') return (toArray(listPayload.sections) || []).map(function (s) { return s.heading })
  if (cfg.type !== 'board') return []
  return (toArray(listPayload.lanes) || []).filter(function (l) { return !l.complete }).map(function (l) { return l.title })
}

// The sound a reminder plays, as the helper's --sound value: none, the
// system default, or the file the user picked among the system sounds.
function soundArgument (config) {
  if (!config || !config.reminderSound) return 'none'
  return config.reminderSoundFile || 'default'
}

function findList (payload, id) {
  var lists = payload && toArray(payload.lists)
  if (!lists) return null
  for (var i = 0; i < lists.length; i++) if (lists[i] && lists[i].id === id) return lists[i]
  return null
}

function listItemCount (listPayload) {
  if (!listPayload || listPayload.state !== 'ok') return 0
  var lanes = toArray(listPayload.lanes)
  if (lanes) {
    // A board counts what waits: the cards of the lanes that are not Complete.
    return lanes.reduce(function (sum, lane) {
      return sum + (lane.complete ? 0 : (toArray(lane.items) || []).length)
    }, 0)
  }
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

// The item keys of one list, without its id.
function listKeys (list) {
  var sections = toArray(list.sections) || toArray(list.lanes)
  var groups = sections ? sections.map(function (s) { return toArray(s.items) || [] }) : [toArray(list.items) || []]
  var keys = []
  groups.forEach(function (items) {
    items.forEach(function (item) { keys.push(item.key) })
  })
  return keys
}

function itemKeys (payload) {
  var keys = []
  ;(toArray(payload && payload.lists) || []).forEach(function (list) {
    listKeys(list).forEach(function (k) { keys.push(list.id + KEY_SEPARATOR + k) })
  })
  return keys
}

function freshKeys (previousPayload, nextPayload) {
  if (!previousPayload) return []
  var before = {}
  itemKeys(previousPayload).forEach(function (k) { before[k] = true })
  return itemKeys(nextPayload).filter(function (k) { return !before[k] })
}

// Whether a folder item still waits for a preview of a kind that is on, or
// for a picture to download. The helper marks an item only until a fetch
// succeeded or failed, so asking again never loops.
function previewsPending (payload, config) {
  var on = { tweet: !!(config && config.tweetPreviews), link: !!(config && config.linkPreviews) }
  return (toArray(payload && payload.lists) || []).some(function (list) {
    return (toArray(list.items) || []).some(function (item) { return on[item.previewKind] === true || item.imagePending === true })
  })
}

function previewArgument (config) {
  var kinds = []
  if (config.tweetPreviews) kinds.push('tweets')
  if (config.linkPreviews) kinds.push('links')
  return kinds.join(',')
}

// Unseen items: the keys of each list that are not in the seen state the
// helper keeps for every screen. A list the state does not know yet counts
// nothing, because the helper starts a new list with all its items seen.
function unseenKeys (payload, seen) {
  var out = []
  if (!seen) return out
  ;(toArray(payload && payload.lists) || []).forEach(function (list) {
    var entry = seen[list.id]
    var keys = entry ? toArray(entry.keys) : null
    if (!keys) return
    var known = {}
    keys.forEach(function (k) { known[k] = true })
    listKeys(list).forEach(function (k) {
      if (!known[k]) out.push(list.id + KEY_SEPARATOR + k)
    })
  })
  return out
}

// What the user has seen when the popup closes: every item of every list
// that was read, as {listId: [keys]} for the helper.
function seenFromPayload (payload) {
  var out = {}
  ;(toArray(payload && payload.lists) || []).forEach(function (list) {
    if (list.state === 'ok') out[list.id] = listKeys(list)
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

// ---- Settings: list editing. Every function returns a new array, so a
// settings write is always a whole, valid list of lists.

function copyLists (lists) {
  return (toArray(lists) || []).map(function (l) { return Object.assign({}, l) })
}

function moveList (lists, index, delta) {
  var out = copyLists(lists)
  var target = index + delta
  if (index < 0 || index >= out.length || target < 0 || target >= out.length) return out
  var item = out[index]
  out[index] = out[target]
  out[target] = item
  return out
}

function updateList (lists, id, field, value) {
  return copyLists(lists).map(function (l) {
    if (l.id === id) l[field] = value
    return l
  })
}

function removeList (lists, id) {
  var out = copyLists(lists)
  for (var i = 0; i < out.length; i++) {
    if (out[i].id === id) return { lists: out.slice(0, i).concat(out.slice(i + 1)), list: out[i], index: i }
  }
  return { lists: out, list: null, index: -1 }
}

function insertList (lists, list, index) {
  var out = copyLists(lists)
  out.splice(Math.max(0, Math.min(index, out.length)), 0, Object.assign({}, list))
  return out
}

function newListId (lists, name) {
  var base = String(name || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 28) || 'list'
  var used = {}
  copyLists(lists).forEach(function (l) { used[l.id] = true })
  if (!used[base]) return base
  for (var n = 2; ; n++) if (!used[base + '-' + n]) return base + '-' + n
}

var COUNT_WORDS = { folder: 'notes', checklist: 'open', sections: 'topics', board: 'cards' }

function listDetail (cfg, payload) {
  var path = cfg.type === 'folder' ? cfg.path.replace(/\/*$/, '/') : cfg.path
  var parts = [path]
  var listPayload = findList(payload, cfg.id)
  if (listPayload && listPayload.state === 'missing') parts.push(cfg.type === 'folder' ? 'folder missing' : 'file missing')
  else if (listPayload && listPayload.state === 'ok') parts.push(listItemCount(listPayload) + ' ' + COUNT_WORDS[cfg.type])
  return parts.join(' · ')
}

// The second action of the removal toast: delete the file of the list too.
// A folder qualifies only when it holds no note; the helper checks again.
function trashLabel (cfg, payload) {
  var list = findList(payload, cfg.id)
  if (!list || list.state !== 'ok') return ''
  if (cfg.type !== 'folder') return 'Delete the file too'
  return listItemCount(list) === 0 ? 'Delete the folder too' : ''
}

function phoneHowTo (cfg) {
  if (cfg.type === 'board')
    return 'In Obsidian on your phone, install the Kanban plugin and open ' + cfg.path + ' to see the board. To add from the pull-down, add a QuickAdd Capture to ' + cfg.path + ' with "Insert after" set to ## To do (your first lane).'
  if (cfg.type === 'folder')
    return 'In Obsidian on your phone, install ReadItLater and set its inbox folder to ' + cfg.path + '. Then share any link to Obsidian and pick ReadItLater.'
  var setting = cfg.type === 'sections'
    ? 'turn on "Choose heading when capturing"'
    : 'set its format to - [ ] {{VALUE}}'
  return 'In Obsidian on your phone, install QuickAdd, add a Capture to ' + cfg.path + ' and ' + setting +
    '. Then pick "QuickAdd: Run" in Settings > Interface > Configure mobile Quick Action, and pull down in Obsidian to add a line.'
}

if (typeof module !== 'undefined') {
  module.exports = {
    KEY_SEPARATOR: KEY_SEPARATOR,
    toArray: toArray,
    normalizeSettings: normalizeSettings,
    findList: findList,
    soundArgument: soundArgument,
    addTargets: addTargets,
    listItemCount: listItemCount,
    badgeCount: badgeCount,
    itemKeys: itemKeys,
    freshKeys: freshKeys,
    freshInBadgeLists: freshInBadgeLists,
    unseenKeys: unseenKeys,
    seenFromPayload: seenFromPayload,
    previewsPending: previewsPending,
    previewArgument: previewArgument,
    relativeAge: relativeAge,
    clockText: clockText,
    tooltipText: tooltipText,
    keyedSyncPlan: keyedSyncPlan,
    syncStep: syncStep,
    moveList: moveList,
    updateList: updateList,
    removeList: removeList,
    insertList: insertList,
    newListId: newListId,
    listDetail: listDetail,
    trashLabel: trashLabel,
    phoneHowTo: phoneHowTo
  }
}
