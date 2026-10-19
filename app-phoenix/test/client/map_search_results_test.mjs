import assert from "node:assert/strict"
import test from "node:test"
import { createSearchUi } from "../../assets/js/map/ui/search.js"

test("suggestions show through the Rails hidden class", async () => {
  const classes = new Set(["absolute", "hidden"])
  const listeners = {}
  const results = {
    classList: {
      toggle: (name, on) => (on ? classes.add(name) : classes.delete(name)),
    },
    replaceChildren() {},
  }
  const input = {
    value: "",
    addEventListener: (name, fn) => {
      listeners[name] = fn
    },
    removeEventListener() {},
  }
  const document = {
    createElement: () => ({ setAttribute() {}, addEventListener() {} }),
  }
  const ui = createSearchUi({
    input,
    results,
    document,
    search: {
      suggest: async () => ({
        status: "ok",
        suggestions: [{ name: "Sterndamm" }],
      }),
      cancel() {},
    },
    onSelect() {},
    timers: {
      setTimeout: (fn) => {
        fn()
        return 1
      },
      clearTimeout() {},
    },
  })
  input.value = "Stern"
  listeners.input()
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(classes.has("hidden"), false)

  ui.reset()
  assert.equal(classes.has("hidden"), true)
  ui.destroy()
})
