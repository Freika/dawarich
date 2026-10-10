import assert from "node:assert/strict"
import test from "node:test"
import * as changelog from "../../app-phoenix/assets/js/hooks/changelog_widget.js"
import * as achievements from "../../app-phoenix/assets/js/hooks/achievement_unlocks.js"

test("HTTP changelog widget loads only declared config once and disposes its script", () => {
  const nodes = []
  const doc = {
    getElementById: (id) => nodes.find((x) => x.id === id),
    createElement: () => ({
      dataset: {},
      remove() {
        nodes.splice(nodes.indexOf(this), 1)
      },
    }),
    head: { appendChild: (node) => nodes.push(node) },
  }
  const el = {
    dataset: {
      changelogWidgetSrcValue: "https://widgets.example.test/loader.js",
      changelogWidgetSlugValue: "dawarich",
      changelogWidgetVersionValue: "1",
    },
  }
  const dispose = changelog.initializeChangelogWidget(el, doc)
  const other = changelog.initializeChangelogWidget(el, doc)
  assert.equal(nodes.length, 1)
  assert.equal(nodes[0].src, el.dataset.changelogWidgetSrcValue)
  assert.equal(nodes[0].dataset.consent, "granted")
  other()
  assert.equal(nodes.length, 1)
  dispose()
  assert.equal(nodes.length, 0)
})

test("HTTP achievement lifecycle drops stale results and cleans its listeners", async (t) => {
  class Target extends EventTarget {
    listeners = 0
    addEventListener(...args) {
      this.listeners++
      super.addEventListener(...args)
    }
    removeEventListener(...args) {
      this.listeners--
      super.removeEventListener(...args)
    }
  }
  let respond,
    writes = 0
  const win = new Target(),
    doc = new Target(),
    el = new Target()
  doc.hidden = false
  doc.activeElement = null
  doc.querySelector = (selector) =>
    selector.startsWith("meta") ? { content: "synthetic-csrf" } : null
  el.dataset = { userId: "7", nextUrl: "/achievements/unlocks/next" }
  Object.defineProperty(el, "innerHTML", {
    set() {
      writes++
    },
  })
  const storage = new Map(),
    timers = new Map()
  const globals = {
    window: win,
    document: doc,
    sessionStorage: {
      getItem: (k) => storage.get(k) || null,
      setItem: (k, v) => storage.set(k, v),
      removeItem: (k) => storage.delete(k),
    },
    fetch: () =>
      new Promise((resolve) => {
        respond = resolve
      }),
    setTimeout: (fn, ms) => {
      const id = timers.size + 1
      timers.set(id, { fn, ms })
      return id
    },
    clearTimeout: (id) => timers.delete(id),
  }
  for (const [key, value] of Object.entries(globals)) {
    const old = Object.getOwnPropertyDescriptor(globalThis, key)
    Object.defineProperty(globalThis, key, { configurable: true, value })
    t.after(() => {
      if (old) Object.defineProperty(globalThis, key, old)
      else delete globalThis[key]
    })
  }
  t.mock.method(console, "error", () => {})
  const dispose = achievements.initializeAchievementUnlocks(el)
  assert.equal(win.listeners, 2)
  assert.equal(doc.listeners, 1)
  assert.equal(el.listeners, 1)
  dispose()
  respond({
    ok: true,
    status: 200,
    json: async () => ({
      id: 7,
      token: "synthetic-claim",
      html: "<article>Visible</article>",
      batch_end_id: 7,
    }),
  })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(writes, 0)
  assert.equal(win.listeners, 0)
  assert.equal(doc.listeners, 0)
  assert.equal(el.listeners, 0)
  assert.equal(timers.size, 0)
})
