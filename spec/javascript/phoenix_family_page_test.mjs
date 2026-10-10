import assert from "node:assert/strict"
import test from "node:test"
import { FamilyMap } from "../../app-phoenix/assets/js/hooks/family_map.js"

function fixture(loader) {
  const events = new Map(),
    empty = { hidden: false },
    canvas = { hidden: true, replaceChildren() {} }
  const maps = [],
    markers = []
  class MapView {
    constructor() {
      maps.push(this)
    }
    addControl() {}
    fitBounds() {}
    flyTo(options) {
      this.center = options.center
    }
    remove() {
      this.removed = true
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
  const library = {
    maplibre: { Map: MapView, Marker, NavigationControl: class {} },
    style: {},
  }
  const hook = {
    ...FamilyMap,
    el: {
      closest: () => ({ querySelectorAll: () => [] }),
      querySelector: (selector) =>
        selector.includes("empty") ? empty : canvas,
    },
    loader: loader ?? (async () => library),
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
  hook.mounted()
  return { hook, events, empty, canvas, maps, markers, library }
}
const location = { user_id: 90102, latitude: 51.3397, longitude: 12.3731 }

test("native family snapshot hydrates the consented map and clears refused data", async () => {
  const f = fixture()
  await f.events.get("family-locations")({ locations: [location] })
  assert.equal(f.empty.hidden, true)
  assert.deepEqual(f.markers[0].coordinate, [12.3731, 51.3397])
  f.events.get("family-focus")({ id: location.user_id })
  assert.deepEqual(f.maps[0].center, [12.3731, 51.3397])
  f.events.get("family-clear")({})
  assert.equal(f.maps[0].removed, true)
  assert.equal(f.markers[0].removed, true)
  assert.equal(f.hook.locations.length, 0)
  assert.equal(f.empty.hidden, false)
  f.hook.destroyed()
})

test("native family disconnect cancels pending lazy work and destroys map state", async () => {
  let release
  const f = fixture(
    () =>
      new Promise((resolve) => {
        release = resolve
      }),
  )
  const pending = f.events.get("family-locations")({ locations: [location] })
  f.hook.disconnected()
  release(f.library)
  await pending
  assert.equal(f.maps.length, 0)
  assert.equal(f.hook.locations.length, 0)
  f.hook.reconnected()
  assert.equal(f.hook.pushed, "family_reload")
  f.hook.loader = async () => f.library
  await f.events.get("family-locations")({ locations: [location] })
  f.hook.destroyed()
  assert.equal(f.maps[0].removed, true)
  assert.equal(f.events.size, 0)
})
