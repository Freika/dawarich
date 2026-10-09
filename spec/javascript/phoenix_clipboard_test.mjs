import assert from "node:assert/strict"
import test from "node:test"

const { Clipboard } = await import(
  "../../app-phoenix/assets/js/hooks/clipboard.js"
)

function element(text) {
  const listeners = {}
  const status = { textContent: "" }
  const classes = new Set()
  return {
    dataset: {
      clipboardText: text,
      copiedLabel: "Copied",
      failedLabel: "Copy failed",
    },
    disabled: false,
    classList: {
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
      contains: (name) => classes.has(name),
    },
    addEventListener: (name, fn) => {
      listeners[name] = fn
    },
    removeEventListener: (name) => {
      delete listeners[name]
    },
    click: () => listeners.click?.({ preventDefault() {} }),
    listeners,
    status,
  }
}

function fixture(t, { writeText, secure = true }) {
  const originals = ["navigator", "window", "document"].map((name) => [
    name,
    Object.getOwnPropertyDescriptor(globalThis, name),
  ])
  t.after(() => {
    for (const [name, descriptor] of originals) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor)
      else delete globalThis[name]
    }
  })
  const writes = []
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
      clipboard: {
        writeText: (text) => {
          writes.push(text)
          return writeText(text)
        },
      },
    },
  })
  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: { isSecureContext: secure, setTimeout: () => 0 },
  })
  Object.defineProperty(globalThis, "document", {
    configurable: true,
    value: {
      body: { appendChild() {}, removeChild() {} },
      createElement: () => ({
        style: {},
        setAttribute() {},
        focus() {},
        select() {},
        setSelectionRange() {},
      }),
      execCommand: () => false,
    },
  })
  const el = element("synthetic-key-0123456789")
  const hook = Object.assign(Object.create(Clipboard), {
    el,
    status: () => el.status,
  })
  hook.mounted()
  return { hook, el, writes }
}

const settle = () => new Promise((resolve) => setImmediate(resolve))

test("copies the exact text and shows the copied label", async (t) => {
  const { el, writes } = fixture(t, { writeText: () => Promise.resolve() })
  el.click()
  await settle()
  assert.deepEqual(writes, ["synthetic-key-0123456789"])
  assert.equal(el.status.textContent, "Copied")
})

test("shows the failure label when the browser refuses the copy", async (t) => {
  const { el } = fixture(t, {
    writeText: () => Promise.reject(new Error("denied")),
  })
  el.click()
  await settle()
  assert.equal(el.status.textContent, "Copy failed")
})

test("removes its click listener when destroyed", (t) => {
  const { hook, el } = fixture(t, { writeText: () => Promise.resolve() })
  hook.destroyed()
  assert.equal(el.listeners.click, undefined)
})
