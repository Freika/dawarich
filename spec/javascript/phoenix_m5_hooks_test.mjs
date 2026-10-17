import assert from "node:assert/strict"
import test from "node:test"
import { hooks } from "../../app-phoenix/assets/js/hooks/index.js"

test("registered RichText mounts and cleans up the native editor", async () => {
  assert.ok(hooks.RichText)
  const listeners = new Map()
  const editor = {
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: (name) => listeners.delete(name),
  }
  const input = { value: "draft", dispatchEvent() {} }
  let cancelled = false
  const hook = {
    ...hooks.RichText,
    el: {
      dataset: { revision: "1" },
      querySelector: (selector) =>
        selector === "trix-editor" ? editor : input,
    },
    handleEvent() {},
    loadEditor: async () => ({
      RichAttachments: class {
        cancelAll() {
          cancelled = true
        }
      },
    }),
  }
  hook.mounted()
  await hook.loading
  assert.equal(hook.el.dataset.editorReady, "true")
  assert.equal(listeners.size, 3)
  assert.equal(input.value, "draft")
  hook.destroyed()
  assert.equal(cancelled, true)
  assert.equal(listeners.size, 0)
})
