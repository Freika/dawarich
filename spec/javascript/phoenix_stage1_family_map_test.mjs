import assert from "node:assert/strict"
import test from "node:test"
import { FamilyMap } from "../../app-phoenix/assets/js/map/shared/family_map.js"

function setup(loader) {
  const events = new Map()
  const shell = { querySelectorAll: () => [] }
  const empty = { hidden: false }
  const canvas = { hidden: true, replaceChildren() {} }
  const el = {
    querySelector: (selector) => (selector.includes("empty") ? empty : canvas),
    closest: () => shell,
  }
  const instance = {
    ...FamilyMap,
    el,
    loader,
    handleEvent(name, fn) {
      events.set(name, fn)
      return name
    },
    removeHandleEvent(name) {
      events.delete(name)
    },
    pushEvent(name) {
      this.pushed = name
    },
  }
  instance.mounted()
  return { instance, events, empty, canvas }
}
function library() {
  const maps = [],
    markers = []
  class FakeMap {
    constructor() {
      this.removed = 0
      maps.push(this)
    }
    addControl() {}
    fitBounds() {}
    flyTo(options) {
      this.focus = options.center
    }
    remove() {
      this.removed++
    }
  }
  class Marker {
    constructor() {
      markers.push(this)
    }
    setLngLat(value) {
      this.coordinate = value
      return this
    }
    addTo() {
      return this
    }
    remove() {
      this.removed = true
    }
  }
  return {
    maplibre: { Map: FakeMap, Marker, NavigationControl: class {} },
    style: {},
    maps,
    markers,
  }
}
const row = { user_id: 2, latitude: 51, longitude: 12, name: "<img src=x>" }

test("revocation during lazy family loading discards the result and removes all private map state", async () => {
  let release
  const lib = library()
  const { instance, events, empty } = setup(
    () =>
      new Promise((resolve) => {
        release = resolve
      }),
  )
  const loading = events.get("family-locations")({ locations: [row] })
  events.get("family-clear")({})
  release(lib)
  await loading
  assert.equal(lib.maps.length, 0)
  assert.equal(instance.locations.length, 0)
  assert.equal(empty.hidden, false)
  instance.destroyed()
})

test("repeated navigation and reconnect leave one family map and no orphan listeners", async () => {
  const lib = library()
  const { instance, events, empty, canvas } = setup(async () => lib)
  await events.get("family-locations")({ locations: [row] })
  assert.equal(lib.maps.length, 1)
  assert.equal(empty.hidden, true)
  assert.equal(canvas.hidden, false)
  events.get("family-focus")({ id: 2 })
  assert.deepEqual(lib.maps[0].focus, [12, 51])
  instance.disconnected()
  assert.equal(lib.maps[0].removed, 1)
  assert.equal(lib.markers[0].removed, true)
  assert.equal(instance.locations.length, 0)
  instance.reconnected()
  assert.equal(instance.pushed, "family_reload")
  await events.get("family-locations")({ locations: [row] })
  assert.equal(lib.maps.length, 2)
  instance.destroyed()
  assert.equal(lib.maps[1].removed, 1)
  assert.equal(events.size, 0)
})

test("family fly-to waits for the authorized lazy map and ignores foreign member IDs", async () => {
  const lib = library()
  let release
  const { instance, events } = setup(
    () =>
      new Promise((resolve) => {
        release = resolve
      }),
  )
  const pending = events.get("family-locations")({ locations: [row] })
  events.get("family-focus")({ id: 2 })
  release(lib)
  await pending
  assert.deepEqual(lib.maps[0].focus, [12, 51])
  events.get("family-focus")({ id: 99 })
  assert.deepEqual(lib.maps[0].focus, [12, 51])
  instance.destroyed()
})
