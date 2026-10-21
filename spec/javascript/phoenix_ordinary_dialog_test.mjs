import assert from "node:assert/strict"
import test from "node:test"
import { OrdinaryDialog } from "../../app-phoenix/assets/js/hooks/ordinary_dialog.js"

test("initial dialog focus cannot reclaim the note field on a later animation frame", () => {
  const previousDocument = globalThis.document
  const previousWindow = globalThis.window
  const frames = []
  const name = {
    focus() {
      globalThis.document.activeElement = this
    },
  }
  const note = {
    focus() {
      globalThis.document.activeElement = this
    },
  }
  globalThis.document = { activeElement: null }
  globalThis.window = { requestAnimationFrame: (fn) => frames.push(fn) }
  const hook = Object.assign(Object.create(OrdinaryDialog), {
    el: {
      querySelector: (selector) =>
        selector === "[data-native-dialog-initial-focus]" ? name : null,
      addEventListener() {},
      removeEventListener() {},
    },
  })
  try {
    hook.mounted()
    assert.equal(globalThis.document.activeElement, name)
    note.focus()
    while (frames.length) frames.shift()()
    assert.equal(globalThis.document.activeElement, note)
    hook.destroyed()
  } finally {
    globalThis.document = previousDocument
    globalThis.window = previousWindow
  }
})

test("ordinary dialog wraps Tab both ways and removes its owned listener", () => {
  const previous = globalThis.document
  const controls = Array.from({ length: 3 }, () => ({
    getClientRects: () => [1],
    focus() {
      globalThis.document.activeElement = this
    },
  }))
  let listener
  globalThis.document = { activeElement: controls[0] }
  const hook = Object.assign(Object.create(OrdinaryDialog), {
    el: {
      querySelectorAll: () => controls,
      addEventListener: (name, fn) => {
        assert.equal(name, "keydown")
        listener = fn
      },
      removeEventListener: (name, fn) => {
        assert.equal(name, "keydown")
        assert.equal(fn, listener)
        listener = null
      },
    },
  })
  let prevented = 0
  const key = (shiftKey) =>
    listener({ key: "Tab", shiftKey, preventDefault: () => prevented++ })
  try {
    hook.mounted()
    key(true)
    assert.equal(globalThis.document.activeElement, controls[2])
    key(false)
    assert.equal(globalThis.document.activeElement, controls[0])
    globalThis.document.activeElement = controls[1]
    key(false)
    assert.equal(prevented, 2)
    assert.equal(globalThis.document.activeElement, controls[1])
    hook.destroyed()
    assert.equal(listener, null)
  } finally {
    globalThis.document = previous
  }
})
