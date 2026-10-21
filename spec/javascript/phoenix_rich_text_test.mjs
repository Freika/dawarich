import assert from "node:assert/strict"
import test from "node:test"

const { RichText } = await import(
  "../../app-phoenix/assets/js/editor/hook.js"
)

class Attachments {
  constructor(hook) {
    this.hook = hook
    this.cancelled = false
  }
  cancelAll() {
    this.cancelled = true
  }
}

function listenerTarget() {
  const listeners = {}
  return {
    listeners,
    addEventListener: (name, fn) => {
      listeners[name] = fn
    },
    removeEventListener: (name, fn) => {
      if (listeners[name] === fn) delete listeners[name]
    },
  }
}

function fixture({ load } = {}) {
  const input = { value: "<div>saved</div>", events: [] }
  input.dispatchEvent = (event) => input.events.push(event.type)
  const editor = {
    ...listenerTarget(),
    editor: {
      loadHTML: (html) => {
        editor.loaded = html
      },
    },
  }
  const el = {
    id: "trip-description",
    dataset: { revision: "1" },
    querySelector: (selector) =>
      selector.startsWith("input")
        ? input
        : selector === "trix-editor"
          ? editor
          : null,
  }
  const handlers = {}
  const pushed = []
  const hook = Object.assign(Object.create(RichText), {
    el,
    loadEditor:
      load || (() => Promise.resolve({ RichAttachments: Attachments })),
    handleEvent: (name, fn) => {
      handlers[name] = fn
    },
    pushEvent: (name, payload, reply) => {
      pushed.push([name, payload])
      reply?.({})
    },
    upload: () => {},
  })
  return { hook, input, editor, handlers, pushed }
}

test("editor joins and unrelated patches preserve unsaved rich text", async () => {
  const { hook, input, editor, handlers } = fixture()
  hook.mounted()
  await hook.loading
  input.value = "<div>unsaved draft</div>"

  hook.updated?.()
  hook.reconnected?.()
  handlers["rich_text:reset"]({
    id: "trip-description",
    revision: 1,
    value: "<div>saved</div>",
  })
  handlers["rich_text:reset"]({ id: "other-editor", revision: 9, value: "" })
  assert.equal(input.value, "<div>unsaved draft</div>")
  assert.equal(editor.loaded, undefined)

  handlers["rich_text:reset"]({
    id: "trip-description",
    revision: 2,
    value: "<div>after save</div>",
  })
  assert.equal(input.value, "<div>after save</div>")
  assert.equal(editor.loaded, "<div>after save</div>")
})

test("typing forwards a form input event for native validation", async () => {
  const { hook, input, editor } = fixture()
  hook.mounted()
  await hook.loading
  editor.listeners["trix-change"]()
  assert.deepEqual(input.events, ["input"])
})

test("editor destroy removes listeners and ignores late import completion", async () => {
  let resolve
  const { hook, editor, el } = (() => {
    const f = fixture({
      load: () =>
        new Promise((r) => {
          resolve = r
        }),
    })
    return { ...f, el: f.hook.el }
  })()
  hook.mounted()
  hook.destroyed()
  resolve({ RichAttachments: Attachments })
  await hook.loading
  assert.deepEqual(Object.keys(editor.listeners), [])
  assert.equal(el.dataset.editorReady, undefined)
  assert.equal(hook.attachments, undefined)

  const live = fixture()
  live.hook.mounted()
  await live.hook.loading
  assert.ok(live.editor.listeners["trix-attachment-add"])
  live.hook.destroyed()
  assert.deepEqual(Object.keys(live.editor.listeners), [])
  assert.equal(live.hook.attachments.cancelled, true)
})

test("a failing editor import marks the editor unavailable without throwing", async () => {
  const { hook } = fixture({ load: () => Promise.reject(new Error("offline")) })
  hook.mounted()
  await hook.loading
  assert.equal(hook.el.dataset.editorError, "true")
})
