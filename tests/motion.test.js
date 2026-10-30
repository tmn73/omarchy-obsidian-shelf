const test = require('node:test')
const assert = require('node:assert/strict')
const Motion = require('../Motion.js')

test('ms uses the shell duration when the shell has one', () => {
  assert.equal(Motion.ms({ duration: () => 0 }, 220), 0)
  assert.equal(Motion.ms({ duration: ms => ms }, 220), 220)
})

test('ms falls back to the plain duration on a shell without Style.duration', () => {
  assert.equal(Motion.ms({}, 220), 220)
  assert.equal(Motion.ms(undefined, 220), 220)
})
