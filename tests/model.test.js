// Pin the zone so clock text is the same on every machine.
process.env.TZ = 'UTC'

const test = require('node:test')
const assert = require('node:assert')
const Model = require('../Model.js')

const LATER = { id: 'read-later', name: 'Read later', type: 'folder', path: 'Read Later' }
const RETRO = { id: 'retro', name: 'Retro', type: 'sections', path: 'Retrospective.md' }
const TODO = { id: 'todo', name: 'Todo', type: 'checklist', path: 'Todo.md' }
const withThree = () => Model.normalizeSettings({ lists: [LATER, RETRO, TODO] }).lists

function payload (later, retro, todo) {
  return {
    ok: true,
    readAt: '2026-10-06T12:22:00+00:00',
    lists: [
      { id: 'read-later', state: 'ok', items: later.map(k => ({ key: k })) },
      { id: 'retro', state: 'ok', sections: [{ heading: 'Good', items: retro.map(k => ({ key: 'Good\n- ' + k })) }] },
      { id: 'todo', state: 'ok', items: todo.map(k => ({ key: '- [ ] ' + k })) }
    ]
  }
}

// ---- normalizeSettings

test('normalizeSettings starts a new user with an empty shelf', () => {
  const config = Model.normalizeSettings({ vaultPath: '/v' })
  assert.deepEqual(config.lists, [])
  assert.equal(config.vaultPath, '/v')
  assert.equal(config.refreshIntervalSec, 10)
  assert.equal(config.syncCheckCommand, '')
  assert.deepEqual(config.errors, [])
})

test('normalizeSettings copies a foreign array-like into a plain array', () => {
  const config = Model.normalizeSettings({ lists: { length: 1, 0: TODO } })
  assert.ok(Array.isArray(config.lists))
  assert.deepEqual(config.lists.map(l => l.id), ['todo'])
})

test('normalizeSettings parses lists given as a JSON string', () => {
  const config = Model.normalizeSettings({ lists: JSON.stringify([LATER]) })
  assert.deepEqual(config.lists.map(l => l.id), ['read-later'])
})

test('normalizeSettings drops an entry without a type and reports it', () => {
  const config = Model.normalizeSettings({ lists: [TODO, { id: 'x', name: 'X', path: 'X.md' }] })
  assert.deepEqual(config.lists.map(l => l.id), ['todo'])
  assert.deepEqual(config.errors, ['List 2 has no valid type'])
})

test('normalizeSettings drops duplicate ids and bad ids', () => {
  const config = Model.normalizeSettings({ lists: [TODO, TODO, { id: 'Bad Id', name: 'B', type: 'checklist', path: 'b.md' }] })
  assert.deepEqual(config.lists.map(l => l.id), ['todo'])
  assert.deepEqual(config.errors, ['List 2 repeats the id todo', 'List 3 has no valid id'])
})

test('normalizeSettings clamps refreshIntervalSec to 10..600', () => {
  assert.equal(Model.normalizeSettings({ refreshIntervalSec: 2 }).refreshIntervalSec, 10)
  assert.equal(Model.normalizeSettings({ refreshIntervalSec: 9999 }).refreshIntervalSec, 600)
  assert.equal(Model.normalizeSettings({ refreshIntervalSec: 'x' }).refreshIntervalSec, 10)
})

test('normalizeSettings defaults badge by type and onDone to delete', () => {
  const lists = withThree()
  assert.deepEqual(lists.map(l => l.badge), [true, false, true])
  assert.equal(lists[2].onDone, 'delete')
  const own = Model.normalizeSettings({ lists: [Object.assign({}, RETRO, { badge: true })] }).lists
  assert.equal(own[0].badge, true)
})

// ---- counts

test('listItemCount counts items and section items', () => {
  const p = payload(['a', 'b'], ['x', 'y', 'z'], [])
  assert.equal(Model.listItemCount(p.lists[0]), 2)
  assert.equal(Model.listItemCount(p.lists[1]), 3)
  assert.equal(Model.listItemCount({ state: 'missing' }), 0)
})

test('badgeCount ignores sections and missing lists', () => {
  const p = payload(['a'], ['x', 'y'], ['t1', 't2'])
  const lists = withThree()
  assert.equal(Model.badgeCount(p, lists), 3)
  p.lists[2] = { id: 'todo', state: 'missing', message: 'Todo.md not found' }
  assert.equal(Model.badgeCount(p, lists), 1)
  assert.equal(Model.badgeCount(null, lists), 0)
})

// ---- fresh items

test('freshKeys is empty on the first read', () => {
  assert.deepEqual(Model.freshKeys(null, payload(['a'], [], [])), [])
})

test('freshKeys returns only new keys', () => {
  const before = payload(['a'], ['x'], ['t1'])
  const after = payload(['n', 'a'], ['x', 'y'], ['t1'])
  assert.deepEqual(Model.freshKeys(before, after), ['read-later\u0000n', 'retro\u0000Good\n- y'])
})

// ---- text

test('relativeAge boundaries', () => {
  const now = Date.parse('2026-10-06T12:00:00Z')
  const at = s => new Date(now - s * 1000).toISOString()
  assert.equal(Model.relativeAge(at(59), now), 'now')
  assert.equal(Model.relativeAge(at(60), now), '1m')
  assert.equal(Model.relativeAge(at(3600), now), '1h')
  assert.equal(Model.relativeAge(at(86400), now), '1d')
})

test('clockText gives local hours and minutes', () => {
  assert.equal(Model.clockText('2026-10-06T07:22:00+00:00'), '07:22')
  assert.equal(Model.clockText(''), '')
})

test('tooltipText lists only non-zero badge lists', () => {
  const lists = withThree()
  assert.equal(Model.tooltipText(payload(['a', 'b', 'c'], ['x'], ['t']), lists), '3 read later, 1 todo')
  assert.equal(Model.tooltipText(payload([], ['x'], ['t']), lists), '1 todo')
  assert.equal(Model.tooltipText(payload([], [], []), lists), 'Nothing on the shelf')
})

// ---- keyed sync

function apply (current, plan) {
  const out = current.slice()
  plan.remove.forEach(i => out.splice(i, 1))
  plan.insert.forEach(op => out.splice(op.index, 0, op.key))
  return out
}

test('keyedSyncPlan turns abc into acd', () => {
  const plan = Model.keyedSyncPlan(['a', 'b', 'c'], ['a', 'c', 'd'])
  assert.deepEqual(plan, { remove: [1], insert: [{ index: 2, key: 'd' }] })
})

test('keyedSyncPlan inserts a new item at the top', () => {
  const plan = Model.keyedSyncPlan(['a', 'b'], ['n', 'a', 'b'])
  assert.deepEqual(plan, { remove: [], insert: [{ index: 0, key: 'n' }] })
})

test('keyedSyncPlan reaches the target when kept keys change order', () => {
  const current = ['a', 'b', 'c']
  const next = ['c', 'a', 'x']
  assert.deepEqual(apply(current, Model.keyedSyncPlan(current, next)), next)
})

// ---- fresh items in the bar

test('freshInBadgeLists counts only fresh keys of badge lists', () => {
  const lists = withThree()
  const fresh = ['read-later\u0000n', 'retro\u0000Good\n- y', 'todo\u0000- [ ] t']
  assert.equal(Model.freshInBadgeLists(fresh, lists), 2)
  assert.equal(Model.freshInBadgeLists([], lists), 0)
})

// ---- Obsidian Sync guide

test('normalizeSettings turns the Obsidian Sync guide on by default', () => {
  assert.equal(Model.normalizeSettings({}).obsidianSync, true)
  assert.equal(Model.normalizeSettings({ obsidianSync: false }).obsidianSync, false)
  assert.equal(Model.normalizeSettings({ obsidianSync: 'false' }).obsidianSync, false)
})

test('syncStep names the next step and its button', () => {
  assert.equal(Model.syncStep('no-client').button, 'Install Obsidian Headless')
  assert.equal(Model.syncStep('logged-out').button, 'Log in')
  assert.equal(Model.syncStep('unlinked').button, 'Link this vault')
  assert.equal(Model.syncStep('stopped').button, 'Start background sync')
  assert.equal(Model.syncStep('running'), null)
  assert.equal(Model.syncStep(''), null)
})

// ---- Unseen items (kept until the popup has been opened and closed)

test('unseenKeys lists the items that are not in the seen state', () => {
  const p = payload(['n1', 'a'], ['x'], ['t'])
  const seen = { 'read-later': { path: 'Read Later', keys: ['a'] }, retro: { path: 'R.md', keys: ['Good\n- x'] }, todo: { path: 'Todo.md', keys: [] } }
  assert.deepEqual(Model.unseenKeys(p, seen), ['read-later\u0000n1', 'todo\u0000- [ ] t'])
})

test('unseenKeys counts nothing for a list the seen state does not know yet', () => {
  assert.deepEqual(Model.unseenKeys(payload(['a'], [], []), { todo: { path: 'Todo.md', keys: [] } }), [])
  assert.deepEqual(Model.unseenKeys(payload(['a'], [], []), null), [])
})

test('seenFromPayload takes every item key of the lists that were read', () => {
  const p = payload(['a'], ['x'], ['t'])
  p.lists.push({ id: 'gone', state: 'missing' })
  assert.deepEqual(Model.seenFromPayload(p), { 'read-later': ['a'], retro: ['Good\n- x'], todo: ['- [ ] t'] })
})

test('normalizeSettings keeps tweet previews off unless asked', () => {
  assert.equal(Model.normalizeSettings({}).tweetPreviews, false)
  assert.equal(Model.normalizeSettings({ tweetPreviews: true }).tweetPreviews, true)
  assert.equal(Model.normalizeSettings({ tweetPreviews: 'true' }).tweetPreviews, true)
})

test('previewsPending asks only for the preview kinds that are on', () => {
  const p = { lists: [{ id: 'read-later', state: 'ok', items: [{ key: 'a', previewKind: '' }, { key: 'b', previewKind: 'link' }] }] }
  assert.equal(Model.previewsPending(p, { tweetPreviews: false, linkPreviews: true }), true)
  assert.equal(Model.previewsPending(p, { tweetPreviews: true, linkPreviews: false }), false)
  p.lists[0].items[1].previewKind = 'tweet'
  assert.equal(Model.previewsPending(p, { tweetPreviews: true, linkPreviews: false }), true)
  assert.equal(Model.previewsPending(null, { tweetPreviews: true, linkPreviews: true }), false)
})

test('previewArgument names the kinds for the helper', () => {
  assert.equal(Model.previewArgument({ tweetPreviews: true, linkPreviews: true }), 'tweets,links')
  assert.equal(Model.previewArgument({ tweetPreviews: false, linkPreviews: true }), 'links')
})

test('normalizeSettings turns link previews on unless asked not to', () => {
  assert.equal(Model.normalizeSettings({}).linkPreviews, true)
  assert.equal(Model.normalizeSettings({ linkPreviews: false }).linkPreviews, false)
})

// ---- Settings: list editing

const THREE = withThree()

test('moveList swaps with the neighbour and ignores moves past an end', () => {
  assert.deepEqual(Model.moveList(THREE, 0, 1).map(l => l.id), ['retro', 'read-later', 'todo'])
  assert.deepEqual(Model.moveList(THREE, 0, -1).map(l => l.id), ['read-later', 'retro', 'todo'])
  assert.deepEqual(Model.moveList(THREE, 2, 1).map(l => l.id), ['read-later', 'retro', 'todo'])
})

test('updateList changes one field of one list and leaves the input alone', () => {
  const next = Model.updateList(THREE, 'todo', 'badge', false)
  assert.equal(next[2].badge, false)
  assert.equal(THREE[2].badge, true)
})

test('removeList and insertList round-trip for undo', () => {
  const removed = Model.removeList(THREE, 'retro')
  assert.deepEqual(removed.lists.map(l => l.id), ['read-later', 'todo'])
  assert.equal(removed.index, 1)
  assert.deepEqual(Model.insertList(removed.lists, removed.list, removed.index).map(l => l.id), ['read-later', 'retro', 'todo'])
})

test('newListId makes a unique id from the name', () => {
  assert.equal(Model.newListId(THREE, 'Meeting agenda'), 'meeting-agenda')
  assert.equal(Model.newListId(THREE, 'Todo'), 'todo-2')
  assert.equal(Model.newListId(THREE, '!!!'), 'list')
})

test('trashLabel offers to delete a file, or a folder only when it is empty', () => {
  const p = { lists: [
    { id: 'read-later', state: 'ok', items: [] },
    { id: 'retro', state: 'ok', sections: [] },
    { id: 'todo', state: 'missing' }
  ] }
  assert.equal(Model.trashLabel(THREE[0], p), 'Delete the folder too')
  assert.equal(Model.trashLabel(THREE[1], p), 'Delete the file too')
  assert.equal(Model.trashLabel(THREE[2], p), '')
  assert.equal(Model.trashLabel(THREE[1], null), '')
  const full = { lists: [{ id: 'read-later', state: 'ok', items: [{ key: 'a' }] }] }
  assert.equal(Model.trashLabel(THREE[0], full), '')
})

test('listDetail describes a list for the settings row', () => {
  const p = { lists: [{ id: 'read-later', state: 'ok', items: [{ key: 'a' }, { key: 'b' }] }, { id: 'todo', state: 'missing' }] }
  // The row icon already shows the kind, so the line names the place and the count.
  assert.equal(Model.listDetail(THREE[0], p), 'Read Later/ · 2 notes')
  assert.equal(Model.listDetail(THREE[2], p), 'Todo.md · file missing')
  assert.equal(Model.listDetail(THREE[1], null), 'Retrospective.md')
})

test('phoneHowTo names the right plugin for each kind', () => {
  assert.match(Model.phoneHowTo(THREE[0]), /ReadItLater.*Read Later/)
  assert.match(Model.phoneHowTo(THREE[2]), /QuickAdd.*Todo\.md/)
})

test('phoneHowTo gives the setting that makes each capture land right', () => {
  assert.match(Model.phoneHowTo(THREE[2]), /- \[ \] \{\{VALUE\}\}/)
  assert.match(Model.phoneHowTo(THREE[1]), /Choose heading when capturing/)
  assert.match(Model.phoneHowTo(THREE[1]), /Settings > Interface > Configure mobile Quick Action/)
})

// ---- Boards

const BOARD = {
  id: 'b',
  state: 'ok',
  datesOn: true,
  lanes: [
    { title: 'To do', complete: false, items: [{ key: 'a', text: 'a', date: '', time: '', checked: false }] },
    { title: 'In progress', complete: false, items: [{ key: 'b', text: 'b', date: '2026-10-06', time: '14:00', checked: false }] },
    { title: 'Done', complete: true, items: [{ key: 'z', text: 'z', date: '', time: '', checked: true }] }
  ]
}

test('a board counts the cards of its open lanes', () => {
  assert.equal(Model.listItemCount(BOARD), 2)
})

test('board cards have keys in every lane', () => {
  assert.deepEqual(Model.itemKeys({ lists: [BOARD] }), ['b\u0000a', 'b\u0000b', 'b\u0000z'])
})

test('a board row counts cards and its phone how-to names the Kanban plugin', () => {
  const cfg = { id: 'b', type: 'board', path: 'Todo.md' }
  assert.equal(Model.listDetail(cfg, { lists: [Object.assign({}, BOARD, { id: 'b' })] }), 'Todo.md · 2 cards')
  assert.match(Model.phoneHowTo(cfg), /Kanban plugin.*Todo\.md/)
  assert.match(Model.phoneHowTo(cfg), /## To do/)
})

test('normalizeSettings accepts boards, their reminder switch and the summary time', () => {
  const s = Model.normalizeSettings({ lists: [{ id: 'b', name: 'Board', type: 'board', path: 'B.md' }, { id: 'c', name: 'C', type: 'board', path: 'C.md', remind: false }] })
  assert.deepEqual(s.errors, [])
  assert.equal(s.lists[0].remind, true)
  assert.equal(s.lists[1].remind, false)
  assert.equal(s.lists[0].badge, true)
  assert.equal(s.reminderTime, '09:00')
  assert.equal(Model.normalizeSettings({ reminderTime: '07:30' }).reminderTime, '07:30')
  assert.equal(Model.normalizeSettings({ reminderTime: '7h' }).reminderTime, '09:00')
})

test('addTargets gives the headings of a notes list and the open lanes of a board', () => {
  assert.deepEqual(Model.addTargets({ type: 'board' }, BOARD), ['To do', 'In progress'])
  assert.deepEqual(Model.addTargets({ type: 'sections' }, { sections: [{ heading: 'Good' }, { heading: 'Bad' }] }), ['Good', 'Bad'])
  assert.deepEqual(Model.addTargets({ type: 'checklist' }, { items: [] }), [])
  assert.deepEqual(Model.addTargets(null, null), [])
})

test('normalizeSettings keeps a reminder sound on by default and its file', () => {
  const s = Model.normalizeSettings({})
  assert.equal(s.reminderSound, true)
  assert.equal(s.reminderSoundFile, '')
  assert.equal(Model.normalizeSettings({ reminderSound: false }).reminderSound, false)
  assert.equal(Model.normalizeSettings({ reminderSound: 'false' }).reminderSound, false)
  assert.equal(Model.normalizeSettings({ reminderSoundFile: '/usr/share/sounds/freedesktop/stereo/bell.oga' }).reminderSoundFile, '/usr/share/sounds/freedesktop/stereo/bell.oga')
})

test('soundArgument tells the helper which sound a reminder plays', () => {
  assert.equal(Model.soundArgument({ reminderSound: false, reminderSoundFile: '/a.oga' }), 'none')
  assert.equal(Model.soundArgument({ reminderSound: true, reminderSoundFile: '' }), 'default')
  assert.equal(Model.soundArgument({ reminderSound: true, reminderSoundFile: '/a.oga' }), '/a.oga')
})

test('previewsPending asks for images to download even with previews off', () => {
  const p = { lists: [{ id: 'read-later', state: 'ok', items: [{ key: 'a', previewKind: '', imagePending: true }] }] }
  assert.equal(Model.previewsPending(p, { tweetPreviews: false, linkPreviews: false }), true)
})
