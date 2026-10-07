import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(new URL("../../app-phoenix/priv/static/js/family_page.js", import.meta.url), "utf8")
const { familyPage, familyLastSeen } = await import(`data:text/javascript;base64,${Buffer.from(source.replace(/^import .*\n/gm, "")).toString("base64")}`)

const location = { user_id: 90102, email: "a-member@a9fpl.dawarich.test", latitude: 51.3397, longitude: 12.3731, timestamp: 1791021300 }

const deferred = () => {
  let resolve
  const promise = new Promise((done) => { resolve = done })
  return { promise, resolve }
}

const fixture = (fetch) => {
  const handlers = new Map()
  const classes = new Set()
  const slot = { textContent: "", hidden: true }
  const row = {
    dataset: { familyMemberId: "90102" },
    classList: { add: (name) => classes.add(name), remove: (name) => classes.delete(name) },
    querySelector: () => slot,
  }
  const emptyClasses = new Set()
  const empty = {
    classList: {
      toggle(name, force) {
        const present = force ?? !emptyClasses.has(name)
        if (present) emptyClasses.add(name)
        else emptyClasses.delete(name)
        return present
      },
      contains: (name) => emptyClasses.has(name),
    },
  }
  const el = {
    querySelectorAll: () => [row],
    querySelector: () => empty,
    addEventListener: (event, handler) => handlers.set(event, handler),
    removeEventListener: (event, handler) => { if (handlers.get(event) === handler) handlers.delete(event) },
  }
  const controller = {
    locationsValue: [],
    maps: [],
    async initMap() {
      this.map = { removed: false, loaded: () => true, flyTo: (options) => { this.flight = options }, remove() { this.removed = true } }
      this.maps.push(this.map)
    },
    disconnect() { this.map?.remove(); this.map = null },
    connect() {},
  }
  const hook = familyPage({ fetch, controller: async () => controller, lastSeen: () => "· 5 minutes ago" })
  hook.el = el
  return { hook, controller, row, slot, empty, classes, handlers }
}

test("family hook hydrates consented member map and clears refused data", async () => {
  const el = { dataset: { familyTimeAgo: JSON.stringify({ middot: "·", ago: "%{time} ago", words: { x_minutes: { one: "1 minute", other: "%{count} minutes" } } }) } }
  assert.equal(familyLastSeen(location, el, (location.timestamp + 300) * 1000), "· 5 minutes ago")
  const calls = []
  let status = 200
  const f = fixture(async (url, options) => {
    calls.push([url, options])
    return { ok: status === 200, status, json: async () => [location] }
  })
  await f.hook.mounted()
  assert.equal(calls[0][0], "/family/locations.json")
  assert.equal(calls[0][1].credentials, "same-origin")
  assert.equal(calls[0][1].cache, "no-store")
  assert.equal(calls[0][1].headers.Accept, "application/json")
  assert.deepEqual(f.controller.locationsValue, [location])
  assert.equal(f.empty.classList.contains("hidden"), true)
  assert.equal(f.slot.textContent, "· 5 minutes ago")
  assert.equal(f.classes.has("cursor-pointer"), true)
  f.handlers.get("click")({ target: { closest: () => f.row } })
  assert.deepEqual(f.controller.flight.center, [12.3731, 51.3397])
  const map = f.controller.map
  status = 403
  await f.hook.reconnected()
  assert.equal(map.removed, true)
  assert.deepEqual(f.controller.locationsValue, [])
  assert.equal(f.empty.classList.contains("hidden"), false)
  assert.equal(f.slot.textContent, "")
  assert.equal(f.classes.has("cursor-pointer"), false)
})

test("family hook destroys map and cancels work on disconnect", async () => {
  const pending = deferred()
  let signal
  let wait = false
  const f = fixture(async (_url, options) => {
    signal = options.signal
    if (wait) await pending.promise
    return { ok: true, json: async () => [location] }
  })
  await f.hook.mounted()
  const map = f.controller.map
  wait = true
  const refresh = f.hook.reconnected()
  await Promise.resolve()
  f.hook.disconnected()
  assert.equal(signal.aborted, true)
  assert.equal(map.removed, true)
  assert.deepEqual(f.controller.locationsValue, [])
  pending.resolve()
  await refresh
  assert.equal(f.controller.map, null)
  assert.equal(f.controller.maps.length, 1)
  f.hook.destroyed()
  assert.equal(f.handlers.size, 0)
})
