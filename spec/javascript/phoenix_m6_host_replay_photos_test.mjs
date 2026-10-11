import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("closing replay releases photo popups density listeners and day-owned thumbnails", async () => {
  const markers = [],
    popups = []
  const library = {
    Marker: class {
      constructor({ element }) {
        this.element = element
        markers.push(this)
      }
      setLngLat() {
        return this
      }
      addTo() {
        return this
      }
      remove() {
        this.removed = true
      }
    },
    Popup: class {
      constructor() {
        popups.push(this)
      }
      setLngLat() {
        return this
      }
      setHTML() {
        return this
      }
      addTo() {
        return this
      }
      on() {
        return this
      }
      off() {
        return this
      }
      remove() {
        this.removed = true
      }
    },
  }
  const f = fixture({}, { library })
  const density = new Element(),
    stack = new Element()
  f.nodes.set("[data-replay-density]", density)
  f.nodes.set("[data-replay-photos]", stack)
  f.reader.read = async () => ({ data: new Blob(["synthetic"]) })
  const points = [
    { timestamp: 1774771200, longitude: 13, latitude: 52 },
    { timestamp: 1774771800, longitude: 13.1, latitude: 52.1 },
    { timestamp: 1774857600, longitude: 13.2, latitude: 52.2 },
  ]
  f.owner.source.snapshot = async () => ({
    points,
    photos: points.map((p, id) => ({
      id,
      longitude: p.longitude,
      latitude: p.latitude,
      taken_at: new Date(p.timestamp * 1000).toISOString(),
      source: "immich",
      filename: `photo-${id}`,
    })),
  })
  await f.owner.mount()
  await f.owner.replay.open()
  assert.equal(density.children.length, 48)
  assert.equal(markers.length, 1)
  const firstBar = density.children[0]
  const firstCard = stack.children[0]
  firstCard.emit("click", { stopPropagation() {} })
  assert.equal(popups.length, 1)
  f.owner.replay.seek(1200)
  assert.equal(markers.length, 2)
  f.owner.replay.manager.nextDay()
  f.owner.replay.seek(0)
  assert.equal(markers[0].removed, true)
  assert.equal(markers[1].removed, true)
  assert.equal(popups[0].removed, true)
  assert.equal(markers.length, 3)
  f.owner.replay.close()
  assert.equal(markers[2].removed, true)
  assert.equal(stack.children.length, 0)
  assert.equal(density.children.length, 0)
  assert.equal(firstBar.listeners.get("click").size, 0)
  assert.equal(firstCard.listeners.get("click").size, 0)
  f.owner.destroy()
})

test("changing replay dates removes old photos before loading the replacement range", async () => {
  const markers = []
  const library = {
    Marker: class {
      constructor({ element }) {
        this.element = element
        markers.push(this)
      }
      setLngLat() {
        return this
      }
      addTo() {
        return this
      }
      remove() {
        this.removed = true
      }
    },
  }
  const f = fixture({}, { library })
  const stack = new Element()
  f.nodes.set("[data-replay-photos]", stack)
  f.reader.read = async () => ({ data: new Blob(["synthetic"]) })
  f.owner.source.snapshot = async () => ({
    points: [{ timestamp: 1774771200, longitude: 13, latitude: 52 }],
    photos: [
      { id: 1, longitude: 13, latitude: 52, taken_at: "2026-03-29T08:00:00Z" },
    ],
  })
  await f.owner.mount()
  await f.owner.replay.open()
  assert.equal(markers.length, 1)
  let resolve
  f.owner.source.snapshot = () =>
    new Promise((done) => {
      resolve = done
    })
  const changed = f.owner.update({
    ...f.owner.config,
    revision: 2,
    range: { ...f.owner.config.range, startAt: "2026-03-30T00:00" },
  })
  assert.equal(markers[0].removed, true)
  assert.equal(stack.children.length, 0)
  await new Promise((done) => setImmediate(done))
  assert.equal(typeof resolve, "function")
  f.owner.destroy()
  resolve({ points: [], photos: [] })
  await changed
  assert.equal(f.sources.has("native-replay-marker"), false)
})

test("native map replay hides regular photos until its replay owner closes", async () => {
  const f = fixture({ photosEnabled: true })
  f.map.querySourceFeatures = () => []
  await f.owner.mount()
  f.owner.source.snapshot = async () => ({ points: [], photos: [] })
  await f.owner.replay.open()
  assert.equal(f.owner.photoLayer.visible, false)
  f.owner.replay.close()
  assert.equal(f.owner.photoLayer.visible, true)
  f.owner.destroy()
})
