// How long an animation runs. The shell's Style.duration(ms) turns motion off
// with the no-animations mode, but Omarchy 4.0.6 does not have it yet: there
// the plain duration is used.
//
// The QML files pass their Style in, since a JS library cannot see it.
function ms (style, duration) {
  return style && typeof style.duration === 'function' ? style.duration(duration) : duration
}

if (typeof module !== 'undefined') {
  module.exports = { ms: ms }
}
