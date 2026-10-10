import assert from "node:assert/strict"
import { test } from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

globalThis.CustomEvent ??= class {
  constructor(type, options) {
    this.type = type
    Object.assign(this, options)
  }
}

function setup(f) {
  const events = []
  for (const kind of ["poster", "video"]) {
    const button = new Element()
    const studio = new Element()
    studio.dispatchEvent = (event) => events.push({ kind, event })
    f.nodes.set(`[data-testid="map-button-${kind}"]`, button)
    f.nodes.set(`#native-${kind}-studio`, studio)
  }
  return events
}

test("map launchers dispatch the stable studio source and release listeners on destroy", async () => {
  const f = fixture()
  const events = setup(f)
  await f.owner.mount()
  for (const kind of ["poster", "video", "poster"])
    f.nodes.get(`[data-testid="map-button-${kind}"]`).emit("click")
  assert.deepEqual(
    events.map(({ event }) => event.type),
    [
      "dawarich:poster-studio-open",
      "dawarich:video-studio-open",
      "dawarich:poster-studio-open",
    ],
  )
  assert.ok(events.every(({ event }) => event.detail.source === f.owner.source))
  assert.deepEqual(events[0].event.detail.fallbackBounds(), [
    [12, 51],
    [14, 53],
  ])
  f.owner.destroy()
  f.nodes.get('[data-testid="map-button-video"]').emit("click")
  assert.equal(events.length, 3)
})

test("studio switching works in both directions with the same source and stops after destroy", async () => {
  const f = fixture()
  const events = setup(f)
  await f.owner.mount()
  f.nodes.get('[data-testid="map-button-poster"]').emit("click")
  assert.equal(typeof events[0].event.detail.openVideo, "function")
  events[0].event.detail.openVideo(f.owner.source)
  assert.equal(events[1].kind, "video")
  f.root.emit("dawarich:studio-switch", {
    target: f.nodes.get("#native-video-studio"),
    detail: { studio: "poster", source: f.owner.source },
  })
  assert.equal(events[2].kind, "poster")
  assert.equal(events[2].event.detail.source, f.owner.source)
  f.owner.destroy()
  f.root.emit("dawarich:studio-switch", {
    detail: { studio: "poster", source: f.owner.source },
  })
  assert.equal(events.length, 3)
})

test("native host restores and persists only its user viewport while owning RTL registration", async () => {
  const values = new Map([
    [
      "dawarich:native:map:lastView:user:7",
      JSON.stringify({ center: [13, 52], zoom: 8 }),
    ],
  ])
  const previous = globalThis.localStorage
  globalThis.localStorage = {
    getItem: (key) => values.get(key),
    setItem: (key, value) => values.set(key, value),
  }
  let rtl = 0,
    view
  const f = fixture(
    { namespace: "user:7" },
    {
      library: {
        getRTLTextPluginStatus: () => "unavailable",
        setRTLTextPlugin: async () => rtl++,
      },
    },
  )
  f.map.jumpTo = (value) => (view = value)
  f.map.getCenter = () => ({ lng: 14, lat: 53 })
  await f.owner.mount()
  await Promise.resolve()
  assert.deepEqual(view, { center: [13, 52], zoom: 8 })
  assert.equal(rtl, 1)
  f.map.emit("moveend")
  assert.deepEqual(
    JSON.parse(values.get("dawarich:native:map:lastView:user:7")),
    { center: [14, 53], zoom: 12 },
  )
  f.owner.destroy()
  values.clear()
  f.map.emit("moveend")
  assert.equal(values.size, 0)
  globalThis.localStorage = previous
})
