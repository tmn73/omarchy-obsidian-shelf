process.env.TZ = 'UTC'

const test = require('node:test')
const assert = require('node:assert')
const Board = require('../Board.js')

const card = (text, date = '', time = '', checked = false) => ({ key: text, text, date, time, checked })

const PAYLOAD = {
  id: 'todo',
  state: 'ok',
  datesOn: true,
  lanes: [
    { title: 'To do', complete: false, items: [card('Bike'), card('Later', '2026-10-20'), card('Landlord', '2026-10-03'), card('Dentist', '2026-10-07', '10:00'), card('Bank')] },
    { title: 'In progress', complete: false, items: [card('Slides', '2026-10-06', '14:00')] },
    { title: 'Done', complete: true, items: [card('Bill', '2026-10-01', '', true)] }
  ]
}

test('boardView shows the lane closest to Done first and the Complete lanes last', () => {
  assert.deepEqual(Board.boardView(PAYLOAD).map(l => l.title), ['In progress', 'To do', 'Done'])
})

test('boardView puts dated cards first, oldest on top, then the others in file order', () => {
  const todo = Board.boardView(PAYLOAD)[1]
  assert.deepEqual(todo.items.map(c => c.text), ['Landlord', 'Dentist', 'Later', 'Bike', 'Bank'])
  assert.equal(todo.items[0].lane, 'To do')
})

test('boardView keeps Complete lanes in file order', () => {
  assert.deepEqual(Board.boardView(PAYLOAD)[2].items.map(c => c.text), ['Bill'])
})

test('dateLabel names late, today, tomorrow and later dates', () => {
  const today = '2026-10-06'
  assert.deepEqual(Board.dateLabel(card('a', '2026-10-03'), today), { text: '3 days late', tone: 'late' })
  assert.deepEqual(Board.dateLabel(card('a', '2026-10-05', '09:00'), today), { text: '1 day late', tone: 'late' })
  assert.deepEqual(Board.dateLabel(card('a', '2026-10-06', '14:00'), today), { text: 'Today 14:00', tone: 'today' })
  assert.deepEqual(Board.dateLabel(card('a', '2026-10-06'), today), { text: 'Today', tone: 'today' })
  assert.deepEqual(Board.dateLabel(card('a', '2026-10-07', '10:00'), today), { text: 'Tomorrow 10:00', tone: '' })
  assert.deepEqual(Board.dateLabel(card('a', '2026-10-20'), today), { text: 'Tue 20 Oct', tone: '' })
})

test('dateLabel shows nothing for a done card or a card without a date', () => {
  assert.equal(Board.dateLabel(card('a', '2026-10-03', '', true), '2026-10-06').text, '')
  assert.equal(Board.dateLabel(card('a'), '2026-10-06').text, '')
})

test('dateLabel shows a date in another format as written', () => {
  assert.deepEqual(Board.dateLabel(card('a', '03/10/2026'), '2026-10-06', false), { text: '03/10/2026', tone: '' })
})

test('lateCount counts the late open cards of the boards that notify', () => {
  const payload = { lists: [PAYLOAD] }
  assert.equal(Board.lateCount(payload, [{ id: 'todo', type: 'board', badge: true }], '2026-10-06'), 1)
  assert.equal(Board.lateCount(payload, [{ id: 'todo', type: 'board', badge: false }], '2026-10-06'), 0)
  assert.equal(Board.lateCount(null, [], '2026-10-06'), 0)
})

test('openLanes lists the lanes a new card can go to, in file order', () => {
  assert.deepEqual(Board.openLanes(PAYLOAD), ['To do', 'In progress'])
  assert.deepEqual(Board.openLanes(null), [])
})

test('neighbour finds the lane before or after a card, in file order', () => {
  assert.equal(Board.neighbour(PAYLOAD, 'To do', 1), 'In progress')
  assert.equal(Board.neighbour(PAYLOAD, 'In progress', 1), 'Done')
  assert.equal(Board.neighbour(PAYLOAD, 'To do', -1), '')
})

test('the date picks are counted from today', () => {
  assert.equal(Board.shiftDay('2026-10-06', 1), '2026-10-07')
  assert.equal(Board.shiftDay('2026-10-31', 1), '2026-11-01')
  assert.equal(Board.nextMonday('2026-10-06'), '2026-10-12')
  assert.equal(Board.nextMonday('2026-10-12'), '2026-10-19')
  assert.equal(Board.isoDay(new Date(2026, 9, 6, 23, 30)), '2026-10-06')
})

test('laneTitles lists every lane a card can go to, Complete lanes too', () => {
  assert.deepEqual(Board.laneTitles(PAYLOAD), ['To do', 'In progress', 'Done'])
  assert.deepEqual(Board.laneTitles(null), [])
})

test('statusMatches filters the lanes and offers to create a name that is new', () => {
  const lanes = ['To do', 'In progress', 'Done']
  assert.deepEqual(Board.statusMatches(lanes, ''), { matches: lanes, canCreate: false })
  assert.deepEqual(Board.statusMatches(lanes, ' prog '), { matches: ['In progress'], canCreate: true })
  assert.deepEqual(Board.statusMatches(lanes, 'wait'), { matches: [], canCreate: true })
  assert.deepEqual(Board.statusMatches(lanes, 'done'), { matches: ['Done'], canCreate: false })
})
