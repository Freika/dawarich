import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/imports_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(
  'import BaseController from "./base_controller"',
  "class BaseController {}",
)
const { default: ImportsController } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

function listenerRegistry() {
  const listeners = {}
  return {
    listeners,
    addEventListener(type, listener) {
      listeners[type] = listener
    },
    removeEventListener(type, listener) {
      if (listeners[type] === listener) delete listeners[type]
    },
  }
}

function fixture(t, { statuses = ["processing"], connected = false } = {}) {
  const originals = new Map()
  function install(name, value) {
    if (!originals.has(name)) {
      originals.set(name, Object.getOwnPropertyDescriptor(globalThis, name))
    }
    Object.defineProperty(globalThis, name, {
      configurable: true,
      writable: true,
      value,
    })
  }
  t.after(() => {
    for (const [name, original] of originals) {
      if (original) Object.defineProperty(globalThis, name, original)
      else delete globalThis[name]
    }
  })

  const streamSource = {
    hasAttribute: (name) => name === "connected" && connected,
  }
  const documentEvents = listenerRegistry()
  install("window", {
    location: { href: "http://localhost/imports?page=2&sort=status" },
  })
  install("document", {
    ...documentEvents,
    querySelectorAll: () => [streamSource],
  })
  install(
    "MutationObserver",
    class {
      observe() {}
      disconnect() {}
    },
  )

  const frameEvents = listenerRegistry()
  const frame = {
    ...frameEvents,
    src: null,
    reloads: 0,
    statuses,
    reload() {
      this.reloads += 1
    },
    querySelector(selector) {
      return this.statuses.some((status) =>
        selector.includes(`data-import-status="${status}"`),
      )
        ? {}
        : null
    },
  }
  const controller = new ImportsController()
  controller.element = frame
  return { controller, frame, documentEvents, frameEvents }
}

function streamRender(target) {
  return {
    target: { getAttribute: (name) => (name === "target" ? target : null) },
  }
}

test("the first sync loads the frame from the current page URL", (t) => {
  const { controller, frame } = fixture(t)

  controller.sync()

  assert.equal(frame.src, "http://localhost/imports?page=2&sort=status")
  assert.equal(frame.reloads, 0)
})

test("later syncs reload the frame", (t) => {
  const { controller, frame } = fixture(t)

  controller.sync()
  controller.sync()

  assert.equal(frame.reloads, 1)
})

test("final statuses do not load the frame", (t) => {
  const { controller, frame } = fixture(t, {
    statuses: ["completed", "failed"],
  })

  controller.sync()

  assert.equal(frame.src, null)
  assert.equal(frame.reloads, 0)
})

test("a row broadcast during a load reloads once more after the frame loads", (t) => {
  const { controller, frame, documentEvents, frameEvents } = fixture(t)
  controller.connect()

  controller.sync()
  documentEvents.listeners["turbo:before-stream-render"](
    streamRender("import_7"),
  )
  frameEvents.listeners["turbo:frame-load"]()

  assert.equal(frame.reloads, 1)

  frameEvents.listeners["turbo:frame-load"]()
  assert.equal(frame.reloads, 1)
})

test("unrelated broadcasts during a load do not reload the frame", (t) => {
  const { controller, frame, documentEvents, frameEvents } = fixture(t)
  controller.connect()

  controller.sync()
  documentEvents.listeners["turbo:before-stream-render"](
    streamRender("notifications-badge"),
  )
  frameEvents.listeners["turbo:frame-load"]()

  assert.equal(frame.reloads, 0)
})

test("connecting after the stream is already connected syncs immediately", (t) => {
  const { controller, frame } = fixture(t, { connected: true })

  controller.connect()

  assert.equal(frame.src, "http://localhost/imports?page=2&sort=status")
})

test("disconnect removes its listeners", (t) => {
  const { controller, documentEvents, frameEvents } = fixture(t)
  controller.connect()

  controller.disconnect()

  assert.deepEqual(Object.keys(documentEvents.listeners), [])
  assert.deepEqual(Object.keys(frameEvents.listeners), [])
})
