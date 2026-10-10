import assert from "node:assert/strict"
import { test } from "node:test"
import { fixture, Element } from "./support/native_m6_host_fixture.mjs"

globalThis.CustomEvent ??= class { constructor(type, options) { this.type = type; Object.assign(this, options) } }

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
  for (const kind of ["poster", "video", "poster"]) f.nodes.get(`[data-testid="map-button-${kind}"]`).emit("click")
  assert.deepEqual(events.map(({event}) => event.type), ["dawarich:poster-studio-open", "dawarich:video-studio-open", "dawarich:poster-studio-open"])
  assert.ok(events.every(({event}) => event.detail.source === f.owner.source))
  assert.deepEqual(events[0].event.detail.fallbackBounds(), [[12,51],[14,53]])
  f.owner.destroy()
  f.nodes.get('[data-testid="map-button-video"]').emit("click")
  assert.equal(events.length,3)
})

test("studio switching works in both directions with the same source and stops after destroy", async () => {
  const f = fixture()
  const events = setup(f)
  await f.owner.mount()
  f.nodes.get('[data-testid="map-button-poster"]').emit("click")
  assert.equal(typeof events[0].event.detail.openVideo, "function")
  events[0].event.detail.openVideo(f.owner.source)
  assert.equal(events[1].kind, "video")
  f.root.emit("dawarich:studio-switch", { target: f.nodes.get('#native-video-studio'), detail: {studio: "poster", source: f.owner.source} })
  assert.equal(events[2].kind, "poster")
  assert.equal(events[2].event.detail.source, f.owner.source)
  f.owner.destroy()
  f.root.emit("dawarich:studio-switch", {detail: {studio: "poster", source: f.owner.source} })
  assert.equal(events.length,3)
})
