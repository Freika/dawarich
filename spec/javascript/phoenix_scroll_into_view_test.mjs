import assert from "node:assert/strict"
import test from "node:test"

const { ScrollIntoView } = await import(
  "../../app-phoenix/assets/js/hooks/scroll_into_view.js"
)

function fixture(
  t,
  { scrollWidth, clientWidth, reducedMotion = false, active = true },
) {
  const calls = []
  const current = { scrollIntoView: (options) => calls.push(options) }
  const original = Object.getOwnPropertyDescriptor(globalThis, "window")
  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: { matchMedia: () => ({ matches: reducedMotion }) },
  })
  t.after(() => {
    if (original) Object.defineProperty(globalThis, "window", original)
    else delete globalThis.window
  })
  const hook = Object.assign(Object.create(ScrollIntoView), {
    el: {
      scrollWidth,
      clientWidth,
      querySelector: (selector) =>
        active && selector === ".tab-active" ? current : null,
    },
  })
  return { hook, calls }
}

test("scrolls the active tab into view when the strip overflows", (t) => {
  const { hook, calls } = fixture(t, { scrollWidth: 900, clientWidth: 390 })
  hook.mounted()
  assert.deepEqual(calls, [
    { block: "nearest", inline: "center", behavior: "smooth" },
  ])
})

test("does nothing when every tab already fits", (t) => {
  const { hook, calls } = fixture(t, { scrollWidth: 390, clientWidth: 390 })
  hook.mounted()
  assert.deepEqual(calls, [])
})

test("jumps without animation when the reader prefers reduced motion", (t) => {
  const { hook, calls } = fixture(t, {
    scrollWidth: 900,
    clientWidth: 390,
    reducedMotion: true,
  })
  hook.mounted()
  assert.equal(calls[0].behavior, "auto")
})

test("does nothing without an active tab", (t) => {
  const { hook, calls } = fixture(t, {
    scrollWidth: 900,
    clientWidth: 390,
    active: false,
  })
  hook.mounted()
  assert.deepEqual(calls, [])
})
