import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { afterEach, beforeEach, test } from "node:test"

const CEILING_MS = 30_000

const source = await readFile(
  new URL(
    "../../app/javascript/video_studio/video_renderer.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const { nextIdle } = await import(
  `data:text/javascript;base64,${Buffer.from(withoutImports).toString("base64")}`
)

function fakeMap() {
  const listeners = new Set()
  return {
    once: (_event, callback) => listeners.add(callback),
    off: (_event, callback) => listeners.delete(callback),
    triggerRepaint() {},
    fireIdle: () => {
      for (const callback of [...listeners]) callback()
    },
    listenerCount: () => listeners.size,
  }
}

function fakeDocument(hidden) {
  const listeners = new Set()
  return {
    hidden,
    addEventListener: (_event, callback) => listeners.add(callback),
    removeEventListener: (_event, callback) => listeners.delete(callback),
    setHidden(value) {
      this.hidden = value
      for (const callback of [...listeners]) callback()
    },
    listenerCount: () => listeners.size,
  }
}

function outcomeOf(promise) {
  const outcome = { state: "pending" }
  promise.then(
    () => {
      outcome.state = "resolved"
    },
    (error) => {
      outcome.state = "rejected"
      outcome.message = error.message
    },
  )
  return outcome
}

const settled = () => new Promise((resolve) => setImmediate(resolve))

const realTimers = {
  setTimeout: globalThis.setTimeout,
  clearTimeout: globalThis.clearTimeout,
}
let clock

function fakeClock() {
  const timers = new Map()
  let now = 0
  let nextId = 1
  globalThis.setTimeout = (callback, delay) => {
    timers.set(nextId, { callback, at: now + delay })
    nextId += 1
    return nextId - 1
  }
  globalThis.clearTimeout = (id) => timers.delete(id)
  return {
    tick(ms) {
      now += ms
      for (const [id, timer] of [...timers]) {
        if (timer.at > now) continue
        timers.delete(id)
        timer.callback()
      }
    },
  }
}

beforeEach(() => {
  clock = fakeClock()
})
afterEach(() => Object.assign(globalThis, realTimers))

test("resolves once the map is idle and leaves no listeners behind", async () => {
  globalThis.document = fakeDocument(false)
  const map = fakeMap()
  const outcome = outcomeOf(nextIdle(map))

  map.fireIdle()
  await settled()

  assert.equal(outcome.state, "resolved")
  assert.equal(map.listenerCount(), 0)
  assert.equal(document.listenerCount(), 0)
})

test("stops the export when a visible map never settles", async () => {
  globalThis.document = fakeDocument(false)
  const map = fakeMap()
  const outcome = outcomeOf(nextIdle(map))

  clock.tick(CEILING_MS)
  await settled()

  assert.equal(outcome.state, "rejected")
  assert.match(outcome.message, /map/i)
  assert.equal(map.listenerCount(), 0)
})

test("does not run out of time while the tab is hidden", async () => {
  globalThis.document = fakeDocument(true)
  const map = fakeMap()
  const outcome = outcomeOf(nextIdle(map))

  clock.tick(CEILING_MS * 10)
  await settled()
  assert.equal(outcome.state, "pending")

  document.setHidden(false)
  map.fireIdle()
  await settled()
  assert.equal(outcome.state, "resolved")
})

test("gives a tab that comes back the full time to finish", async () => {
  globalThis.document = fakeDocument(false)
  const map = fakeMap()
  const outcome = outcomeOf(nextIdle(map))

  clock.tick(CEILING_MS - 1)
  document.setHidden(true)
  clock.tick(CEILING_MS * 2)
  document.setHidden(false)
  clock.tick(CEILING_MS - 1)
  await settled()
  assert.equal(outcome.state, "pending")

  clock.tick(1)
  await settled()
  assert.equal(outcome.state, "rejected")
})

test("rejects as cancelled as soon as the render is aborted", async () => {
  globalThis.document = fakeDocument(false)
  const map = fakeMap()
  const controller = new AbortController()
  const outcome = outcomeOf(nextIdle(map, controller.signal))

  controller.abort()
  await settled()

  assert.equal(outcome.state, "rejected")
  assert.equal(outcome.message, "Render cancelled")
  assert.equal(map.listenerCount(), 0)
  assert.equal(document.listenerCount(), 0)
})
