// Board logic for the bar: the order of the lanes and cards, the date labels
// and the date picks. Pure functions, tested under node, imported by QML as
// `import "Board.js" as Board`.

var DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
var MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
var ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

// Arrays from QML models are not always real arrays; copy them.
function arr (value) {
  if (!value || typeof value.length !== 'number') return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function dayNumber (iso) {
  var p = iso.split('-').map(Number)
  return Date.UTC(p[0], p[1] - 1, p[2]) / 86400000
}

function shiftDay (iso, days) {
  return new Date((dayNumber(iso) + days) * 86400000).toISOString().slice(0, 10)
}

function nextMonday (iso) {
  var weekday = new Date(dayNumber(iso) * 86400000).getUTCDay()
  return shiftDay(iso, ((8 - weekday) % 7) || 7)
}

// Today in the local time zone, as the helper writes dates.
function isoDay (date) {
  var m = date.getMonth() + 1
  var d = date.getDate()
  return date.getFullYear() + '-' + (m < 10 ? '0' : '') + m + '-' + (d < 10 ? '0' : '') + d
}

// The lanes as the tab shows them: the open lane closest to Done first, the
// Complete lanes last. In an open lane, dated cards come first, oldest on top.
function boardView (listPayload) {
  var lanes = arr(listPayload && listPayload.lanes)
  var view = function (lane) {
    var items = arr(lane.items).map(function (item, index) {
      var out = {}
      for (var k in item) out[k] = item[k]
      out.lane = lane.title
      out.order = index
      return out
    })
    if (!lane.complete) {
      items.sort(function (a, b) {
        var da = ISO_DATE.test(a.date) ? a.date + ' ' + (a.time || '') : '~'
        var db = ISO_DATE.test(b.date) ? b.date + ' ' + (b.time || '') : '~'
        return da < db ? -1 : da > db ? 1 : a.order - b.order
      })
    }
    return { title: lane.title, complete: !!lane.complete, items: items }
  }
  var open = lanes.filter(function (l) { return !l.complete }).reverse()
  var done = lanes.filter(function (l) { return l.complete })
  return open.concat(done).map(view)
}

// The chip text of a card date, and its tone: late, today or none.
function dateLabel (card, todayIso, datesOn) {
  if (!card || card.checked || !card.date) return { text: '', tone: '' }
  var at = card.time ? ' ' + card.time : ''
  if (datesOn === false || !ISO_DATE.test(card.date)) return { text: card.date + at, tone: '' }
  var days = dayNumber(card.date) - dayNumber(todayIso)
  if (days < 0) return { text: -days + (days === -1 ? ' day late' : ' days late'), tone: 'late' }
  if (days === 0) return { text: 'Today' + at, tone: 'today' }
  if (days === 1) return { text: 'Tomorrow' + at, tone: '' }
  var date = new Date(dayNumber(card.date) * 86400000)
  return { text: DAY_NAMES[date.getUTCDay()] + ' ' + date.getUTCDate() + ' ' + MONTH_NAMES[date.getUTCMonth()] + at, tone: '' }
}

// Late open cards in the boards that notify: they turn the chip count red.
function lateCount (payload, lists, todayIso) {
  var payloads = arr(payload && payload.lists)
  return arr(lists).reduce(function (sum, cfg) {
    if (cfg.type !== 'board' || !cfg.badge) return sum
    var list = payloads.filter(function (p) { return p.id === cfg.id })[0]
    if (!list || list.state !== 'ok' || list.datesOn === false) return sum
    arr(list.lanes).forEach(function (lane) {
      if (lane.complete) return
      arr(lane.items).forEach(function (item) {
        if (!item.checked && ISO_DATE.test(item.date) && item.date < todayIso) sum++
      })
    })
    return sum
  }, 0)
}

// The lanes a new card can go to, in file order.
function openLanes (listPayload) {
  return arr(listPayload && listPayload.lanes).filter(function (l) { return !l.complete }).map(function (l) { return l.title })
}

// Every lane, in file order: the statuses a card can take.
function laneTitles (listPayload) {
  return arr(listPayload && listPayload.lanes).map(function (l) { return l.title })
}

// The status menu: the lanes that hold the typed text, and whether the text
// names a lane that does not exist yet, so Enter can create it.
function statusMatches (titles, query) {
  var q = String(query || '').trim().toLowerCase()
  var all = arr(titles)
  return {
    matches: all.filter(function (t) { return q === '' || t.toLowerCase().indexOf(q) >= 0 }),
    canCreate: q !== '' && !all.some(function (t) { return t.toLowerCase() === q })
  }
}

// The lane before (step -1) or after (step 1) a lane, in file order.
function neighbour (listPayload, title, step) {
  var titles = arr(listPayload && listPayload.lanes).map(function (l) { return l.title })
  var index = titles.indexOf(title) + step
  return index >= 0 && index < titles.length && titles.indexOf(title) >= 0 ? titles[index] : ''
}

if (typeof module !== 'undefined') {
  module.exports = {
    boardView: boardView,
    dateLabel: dateLabel,
    lateCount: lateCount,
    openLanes: openLanes,
    laneTitles: laneTitles,
    statusMatches: statusMatches,
    neighbour: neighbour,
    shiftDay: shiftDay,
    nextMonday: nextMonday,
    isoDay: isoDay
  }
}
