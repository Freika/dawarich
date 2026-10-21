import assert from "node:assert/strict"
import test from "node:test"
import { AchievementUnlocksLifecycle } from "../../app-phoenix/assets/js/hooks/achievement_unlocks.js"

const flush = () => new Promise((resolve) => setImmediate(resolve))

function fixture(t) {
  const runtimes = []
  t.after(() => {
    for (const runtime of runtimes) runtime.stop()
  })
  const requests = [],
    timers = new Map(),
    storage = new Map()
  let timerId = 0,
    focus = 0
  const win = new EventTarget(),
    doc = new EventTarget(),
    el = new EventTarget()
  doc.hidden = false
  doc.activeElement = { isConnected: true, focus: () => focus++ }
  doc.querySelector = (selector) =>
    selector.startsWith("meta") ? { content: "synthetic-csrf" } : null
  el.dataset = {
    userId: "7",
    nextUrl: "/next",
    dismissUrl: "/dismiss",
    seenUrl: "/seen/__ID__",
  }
  el.innerHTML = ""
  el.firstElementChild = { classList: { add() {} } }
  el.querySelector = () => ({ focus: () => focus++ })
  el.replaceChildren = () => {
    el.innerHTML = ""
  }
  const globals = {
    window: win,
    document: doc,
    sessionStorage: {
      getItem: (k) => storage.get(k) || null,
      setItem: (k, v) => storage.set(k, v),
      removeItem: (k) => storage.delete(k),
    },
    matchMedia: () => ({ matches: false }),
    fetch: (url) => new Promise((resolve) => requests.push({ url, resolve })),
    setTimeout: (fn, ms) => {
      const id = ++timerId
      timers.set(id, { fn, ms })
      return id
    },
    clearTimeout: (id) => timers.delete(id),
  }
  for (const [key, value] of Object.entries(globals)) {
    const original = Object.getOwnPropertyDescriptor(globalThis, key)
    Object.defineProperty(globalThis, key, { configurable: true, value })
    t.after(() =>
      original
        ? Object.defineProperty(globalThis, key, original)
        : delete globalThis[key],
    )
  }
  t.mock.method(console, "error", () => {})
  const mount = async (id) => {
    const runtime = new AchievementUnlocksLifecycle(el)
    runtime.start()
    requests.at(-1).resolve({
      ok: true,
      status: 200,
      json: async () => ({
        id,
        token: `synthetic-claim-${id}`,
        batch_end_id: id,
        remaining: 2,
        html: `<article>${id}</article>`,
      }),
    })
    await flush()
    runtimes.push(runtime)
    return runtime
  }
  const snapshot = () =>
    JSON.stringify({
      html: el.innerHTML,
      storage: [...storage],
      focus,
      timers: [...timers.keys()],
      requests: requests.length,
    })
  return { mount, requests, timers, snapshot }
}

for (const action of ["dismiss", "acknowledge", "nextCard"]) {
  test(`disposed ${action} success cannot mutate a remounted HTTP achievement host`, async (t) => {
    const f = fixture(t),
      old = await f.mount(7)
    if (action === "nextCard") old.current.remaining = 1
    const pending = old[action]()
    const response = f.requests.at(-1)
    old.stop()
    await f.mount(8)
    const before = f.snapshot()
    response.resolve({ ok: true, status: 200 })
    await pending
    assert.equal(f.snapshot() === before, true)
  })
}

test("disposed next-card animation cannot resume against a remounted HTTP host", async (t) => {
  const f = fixture(t),
    old = await f.mount(7)
  old.focusAfterLoad = false
  const pending = old.nextCard()
  f.requests.at(-1).resolve({ ok: true, status: 200 })
  await flush()
  const delayed = [...f.timers.values()].find((timer) => timer.ms === 170)
  assert.equal(Boolean(delayed), true)
  old.stop()
  await f.mount(8)
  const before = f.snapshot()
  delayed.fn()
  await pending
  assert.equal(old.focusAfterLoad, false)
  assert.equal(f.snapshot() === before, true)
})
