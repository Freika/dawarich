import assert from "node:assert/strict"
import { test } from "node:test"
import {
  attachViewportStore,
  createViewStore,
} from "../../app-phoenix/assets/js/map/data/view_store.js"
import { registerRTLTextPlugin } from "../../app-phoenix/assets/js/map/style/rtl.js"

function storage() {
  const values = new Map()
  return {
    values,
    getItem: (key) => values.get(key),
    setItem: (key, value) => values.set(key, value),
  }
}
test("viewport persistence contains no credential and is isolated between accounts", () => {
  const cache = storage(),
    a = createViewStore({ storage: cache, namespace: "user:1" }),
    b = createViewStore({ storage: cache, namespace: "user:2" })
  const map = { getCenter: () => ({ lng: 13, lat: 52 }), getZoom: () => 8 }
  a.save(map)
  assert.deepEqual(a.load(), { center: [13, 52], zoom: 8 })
  assert.equal(b.load(), null)
  createViewStore({ storage: cache, namespace: "synthetic-api-key" }).save(map)
  assert.deepEqual(
    [...cache.values.keys()],
    ["dawarich:native:map:lastView:user:1"],
  )
  cache.values.set(
    "dawarich:map:lastView:legacy-hash",
    JSON.stringify({ center: [14, 53], zoom: 9 }),
  )
  assert.equal(b.load(), null)
})
test("account switch clears the old viewport and destruction never writes", () => {
  const cache = storage(),
    handlers = new Map(),
    moves = []
  const map = {
    on: (name, fn) => handlers.set(name, fn),
    off: (name) => handlers.delete(name),
    jumpTo: (view) => moves.push(view),
    getCenter: () => ({ lng: 13, lat: 52 }),
    getZoom: () => 8,
  }
  const owner = attachViewportStore({
    map,
    namespace: "user:1",
    storage: cache,
  })
  handlers.get("moveend")()
  owner.updateNamespace("user:2")
  assert.deepEqual(moves.at(-1), { center: [0, 0], zoom: 1 })
  assert.equal(cache.values.size, 1)
  owner.destroy()
  assert.equal(handlers.size, 0)
  assert.equal(cache.values.size, 1)
})
test("viewport storage refuses malformed data and unavailable storage safely", () => {
  const cache = storage(),
    store = createViewStore({ storage: cache, namespace: "user:1" })
  for (const view of [
    { center: [Infinity, 52], zoom: 8 },
    { center: [181, 52], zoom: 8 },
    { center: [13, 91], zoom: 8 },
    { center: [13, 52], zoom: "8" },
  ]) {
    cache.values.set(
      "dawarich:native:map:lastView:user:1",
      JSON.stringify(view),
    )
    assert.equal(store.load(), null)
  }
  const unavailable = createViewStore({
    namespace: "user:1",
    storage: {
      getItem() {
        throw new Error("unavailable")
      },
      setItem() {
        throw new Error("unavailable")
      },
    },
  })
  assert.equal(unavailable.load(), null)
  assert.equal(
    unavailable.save({
      getCenter: () => ({ lng: 13, lat: 52 }),
      getZoom: () => 8,
    }),
    false,
  )
})
test("RTL registration stays lazy and shared warm libraries are registered once", async () => {
  let calls = 0
  const library = {
    getRTLTextPluginStatus: () => "unavailable",
    async setRTLTextPlugin(url, lazy) {
      assert.equal(url, "/rtl.js")
      assert.equal(lazy, true)
      calls++
    },
  }
  await Promise.all([
    registerRTLTextPlugin(library, "/rtl.js"),
    registerRTLTextPlugin(library, "/rtl.js"),
  ])
  assert.equal(calls, 1)
  await registerRTLTextPlugin(library, "/rtl.js")
  assert.equal(calls, 1)
})
test("RTL load failure produces only a typed refusal and permits retry", async () => {
  const notices = []
  let fail = true,
    calls = 0
  const library = {
    getRTLTextPluginStatus: () => "requested",
    async setRTLTextPlugin() {
      calls++
      if (fail) throw new Error("synthetic-private-url")
    },
  }
  assert.equal(
    await registerRTLTextPlugin(library, "/rtl.js", {
      onError: (code) => notices.push(code),
    }),
    false,
  )
  assert.deepEqual(notices, ["rtl_unavailable"])
  fail = false
  assert.equal(await registerRTLTextPlugin(library, "/rtl.js"), true)
  assert.equal(calls, 2)
})

test("late viewport restore cannot act on a removed map", () => {
  let moves = 0
  const map = {
    on() {},
    off() {},
    jumpTo() {
      moves++
    },
  }
  const owner = attachViewportStore({
    map,
    namespace: "user:1",
    storage: storage(),
  })
  owner.destroy()
  owner.restore()
  owner.updateNamespace("user:2")
  assert.equal(moves, 0)
})
