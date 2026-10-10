import assert from "node:assert/strict"
import test from "node:test"
import {
  clearGalleries,
  openGallery,
  showGallery,
} from "../../app-phoenix/assets/js/hooks/shared_gallery.js"
import { SharedMap } from "../../app-phoenix/assets/js/hooks/shared_map.js"
import { publicRoutes } from "../../app-phoenix/assets/js/hooks/shared_routes.js"

function setup(loader) {
  const events = new Map()
  const canvas = { hidden: true, replaceChildren() {} }
  const empty = { hidden: false }
  const gallery = {
    erased: 0,
    replaceChildren() {
      this.erased++
    },
  }
  const content = { hidden: false }
  const handlers = new Map()
  const el = {
    dataset: { locale: "en" },
    querySelector: (selector) =>
      selector.includes("empty")
        ? empty
        : selector.includes("canvas")
          ? canvas
          : selector.includes("public-content")
            ? content
            : null,
    querySelectorAll: (selector) =>
      selector.includes("details") ? [] : [gallery],
    closest: () => content,
    addEventListener: (name, handler) => handlers.set(name, handler),
    removeEventListener: (name) => handlers.delete(name),
  }
  const instance = {
    ...SharedMap,
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
  return { instance, events, canvas, empty, gallery, content, handlers }
}
function library() {
  const maps = [],
    markers = []
  class FakeMap {
    constructor() {
      this.removed = 0
      this.callbacks = []
      maps.push(this)
    }
    addControl() {}
    fitBounds() {}
    once(_, fn) {
      this.callbacks.push(fn)
    }
    isStyleLoaded() {
      return true
    }
    getSource() {
      return this.source
        ? {
            setData: (data) => {
              this.source.data = data
            },
          }
        : null
    }
    addSource(_, data) {
      this.source = data
    }
    addLayer() {}
    remove() {
      this.removed++
    }
  }
  class Marker {
    constructor(options) {
      this.element = options?.element
      markers.push(this)
    }
    getElement() {
      return this.element
    }
    setLngLat(p) {
      this.coordinate = p
      return this
    }
    addTo() {
      assert.ok(this.coordinate, "MapLibre requires a position before addTo")
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
const snapshot = {
  latest: [[12, 51, 100]],
  points: [
    [12, 51, 100],
    [13, 52, 200],
  ],
  photos: [],
  zone: "UTC",
}

test("revocation during an in-flight public fetch discards its result and removes the map", async () => {
  let release, signal
  const lib = library()
  const { instance, events, content } = setup((options) => {
    signal = options.signal
    return new Promise((resolve) => {
      release = resolve
    })
  })
  const pending = events.get("public-share-snapshot")(snapshot)
  events.get("public-share-clear")({})
  assert.equal(signal.aborted, true)
  release(lib)
  await pending
  assert.equal(lib.maps.length, 0)
  assert.deepEqual(instance.points, [])
  assert.equal(content.hidden, true)
  instance.destroyed()
})

test("disconnect and repeated navigation destroy maps workers fetches and listeners", async () => {
  const lib = library()
  const { instance, events, gallery, content, handlers } = setup(
    async () => lib,
  )
  await events.get("public-share-snapshot")(snapshot)
  assert.equal(lib.maps.length, 1)
  assert.deepEqual(lib.maps[0].source.data.features[0].geometry.coordinates, [
    [12, 51],
    [13, 52],
  ])
  assert.deepEqual(lib.markers[0].coordinate, [12, 51])
  instance.disconnected()
  assert.equal(lib.maps[0].removed, 1)
  assert.equal(lib.markers[0].removed, true)
  assert.deepEqual(instance.points, [])
  assert.equal(content.hidden, true)
  assert.ok(gallery.erased > 0)
  instance.reconnected()
  assert.equal(instance.pushed, "public_reload")
  await events.get("public-share-snapshot")(snapshot)
  instance.destroyed()
  assert.equal(lib.maps[1].removed, 1)
  assert.equal(events.size, 0)
  assert.equal(handlers.size, 0)
})

test("public empty snapshots load no library and late style callbacks cannot restore erased routes", async () => {
  let calls = 0
  const lib = library()
  lib.maplibre.Map.prototype.isStyleLoaded = () => false
  const { instance, events, empty } = setup(async () => {
    calls++
    return lib
  })
  await events.get("public-share-snapshot")({
    latest: [],
    points: [],
    photos: [],
  })
  assert.equal(calls, 0)
  assert.equal(empty.hidden, false)
  await events.get("public-share-snapshot")(snapshot)
  assert.equal(calls, 1)
  instance.disconnected()
  for (const callback of lib.maps[0].callbacks) callback()
  assert.equal(lib.maps[0].source, undefined)
  assert.deepEqual(instance.points, [])
  instance.destroyed()
})

test("public gallery loads authorized day photos lazily and disconnect aborts image sources", () => {
  const previous = globalThis.document
  globalThis.document = {
    createElement() {
      return {
        removeAttribute(name) {
          delete this[name]
        },
      }
    },
  }
  try {
    const content = {
      items: [],
      replaceChildren() {
        this.items = []
      },
      append(image) {
        this.items.push(image)
      },
    }
    const details = {
      open: false,
      dataset: { publicGalleryDay: "2026-05-10" },
      querySelector: () => content,
    }
    const el = {
      querySelector: () => null,
      querySelectorAll: (selector) =>
        selector.includes("details")
          ? [details]
          : selector.includes("img")
            ? content.items
            : [content],
    }
    const photos = [
      {
        taken_at: "2026-05-10T12:00:00Z",
        day_key: "2026-05-10",
        thumbnail_url:
          "/api/v1/shared/synthetic/photos/visible/thumbnail?source=immich",
      },
      {
        taken_at: "2026-05-10T12:00:00Z",
        day_key: "2026-05-10",
        thumbnail_url: "https://foreign.example/photo",
      },
    ]
    showGallery(el, photos, "UTC")
    assert.equal(content.items.length, 0)
    details.open = true
    openGallery(details)
    assert.equal(content.items.length, 1)
    const image = content.items[0]
    assert.equal(image.loading, "lazy")
    clearGalleries(el)
    assert.equal(image.src, undefined)
    assert.equal(content.items.length, 0)
    assert.deepEqual(details.publicPhotos, [])
    openGallery(details)
    assert.equal(content.items.length, 0)
  } finally {
    if (previous) globalThis.document = previous
    else delete globalThis.document
  }
})

test("native public routes preserve gap splitting IDL crossings and day colors", () => {
  const crossed = publicRoutes(
    [
      [179, 45, 100],
      [-179, 45, 200],
    ],
    { zone: "UTC" },
  )
  assert.equal(crossed.features[0].geometry.type, "MultiLineString")
  assert.equal(crossed.features[0].geometry.coordinates[0].at(-1)[0], 180)
  assert.equal(crossed.features[0].geometry.coordinates[1][0][0], -180)
  const gap = publicRoutes(
    [
      [12, 51, 100],
      [12.01, 51.01, 200],
      [13, 52, 6000],
    ],
    { zone: "UTC" },
  )
  assert.equal(gap.features.length, 1)
  assert.equal(gap.features[0].properties.pointCount, 2)
  const at = Date.parse("2026-05-10T12:00:00Z") / 1000
  const days = publicRoutes(
    [
      [12, 51, at],
      [12.01, 51.01, at + 1],
      [13, 52, at + 86400],
      [13.01, 52.01, at + 86401],
    ],
    { zone: "UTC", by_day: true },
  )
  assert.equal(days.features.length, 2)
  assert.notEqual(
    days.features[0].properties.color,
    days.features[1].properties.color,
  )
})

test("a late public style callback cannot replace a newer authorized route", async () => {
  const lib = library()
  lib.maplibre.Map.prototype.isStyleLoaded = () => false
  const { instance, events } = setup(async () => lib)
  await events.get("public-share-snapshot")(snapshot)
  const newer = {
    ...snapshot,
    latest: [],
    points: [
      [14, 53, 300],
      [14.01, 53.01, 400],
    ],
  }
  await events.get("public-share-snapshot")(newer)
  for (const callback of lib.maps[1].callbacks) callback()
  for (const callback of lib.maps[0].callbacks) callback()
  assert.deepEqual(lib.maps[1].source.data.features[0].geometry.coordinates, [
    [14, 53],
    [14.01, 53.01],
  ])
  instance.destroyed()
})

test("public photo markers use authorized thumbnails and abort image sources on disconnect", async () => {
  const previous = globalThis.document
  globalThis.document = {
    createElement() {
      return {
        style: {},
        removeAttribute(name) {
          delete this[name]
        },
      }
    },
  }
  try {
    const lib = library()
    const { instance, events } = setup(async () => lib)
    await events.get("public-share-snapshot")({
      ...snapshot,
      photos: [
        {
          latitude: 51,
          longitude: 12,
          thumbnail_url:
            "/api/v1/shared/synthetic/photos/visible/thumbnail?source=immich",
        },
      ],
    })
    assert.equal(lib.markers.length, 2)
    const image = lib.markers[1].element
    assert.equal(image.loading, "lazy")
    instance.disconnected()
    assert.equal(image.src, undefined)
    assert.equal(lib.markers[1].removed, true)
    instance.destroyed()
  } finally {
    if (previous) globalThis.document = previous
    else delete globalThis.document
  }
})

test("native public replay preserves day time speed follow and point controls and clears timers", async () => {
  const active = new Set()
  const realSet = globalThis.setInterval,
    realClear = globalThis.clearInterval
  globalThis.setInterval = () => {
    const timer = {}
    active.add(timer)
    return timer
  }
  globalThis.clearInterval = (timer) => {
    active.delete(timer)
  }
  try {
    const { PublicReplay } = await import(
      "../../app-phoenix/assets/js/hooks/shared_replay.js"
    )
    const targets = new Map()
    const panel = { hidden: true, classList: { toggle() {} } }
    const root = {
      querySelector(selector) {
        if (selector === "[data-public-replay-panel]") return panel
        const name = selector.match(/="([^"]+)"/)?.[1]
        if (!targets.has(name))
          targets.set(name, {
            value: "",
            textContent: "",
            classList: { toggle() {} },
          })
        return targets.get(name)
      },
    }
    const lib = library()
    const map = new lib.maplibre.Map()
    map.easeTo = ({ center }) => {
      map.center = center
    }
    const at = Date.parse("2026-05-10T12:00:00Z") / 1000
    const replay = new PublicReplay(
      root,
      map,
      lib.maplibre,
      [
        [12, 51, at],
        [12.01, 51.01, at],
        [13, 52, at + 86400],
      ],
      "UTC",
      "de",
    )
    replay.action("toggleReplay")
    assert.equal(panel.hidden, false)
    replay.action("replayScrubberHover", "720")
    assert.equal(targets.get("replayTimeDisplay").textContent, "12:00")
    replay.action("replayCycleNext")
    assert.deepEqual(lib.markers[0].coordinate, [12.01, 51.01])
    replay.action("replayRecenterFollow")
    assert.deepEqual(map.center, [12.01, 51.01])
    replay.action("replaySpeedChange", "4")
    assert.equal(replay.speed, 10)
    replay.action("replayNextDay")
    assert.deepEqual(lib.markers[0].coordinate, [13, 52])
    replay.action("replayPrevDay")
    replay.action("replayTogglePlayback")
    assert.ok(replay.timer)
    replay.clear()
    assert.equal(replay.timer, null)
    assert.equal(panel.hidden, true)
    assert.equal(lib.markers[0].removed, true)
    assert.deepEqual(replay.days, [])
    assert.equal(active.size, 0)
  } finally {
    globalThis.setInterval = realSet
    globalThis.clearInterval = realClear
  }
})

test("first replay draw positions its marker before attaching to MapLibre", async () => {
  const { PublicReplay } = await import(
    "../../app-phoenix/assets/js/hooks/shared_replay.js"
  )
  const lib = library()
  const panel = { hidden: true, classList: { toggle() {} } }
  const root = {
    querySelector: (s) => (s === "[data-public-replay-panel]" ? panel : null),
  }
  const replay = new PublicReplay(
    root,
    new lib.maplibre.Map(),
    lib.maplibre,
    [[12, 51, 100]],
    "UTC",
    "en",
  )
  replay.action("toggleReplay")
  assert.deepEqual(lib.markers[0].coordinate, [12, 51])
  assert.equal(panel.hidden, false)
  replay.clear()
})

for (const ownerZone of ["UTC", "America/New_York"]) {
  test(`day galleries use the authoritative ${ownerZone} day for local midnight in a different browser zone`, () => {
    const previous = process.env.TZ
    process.env.TZ = "Europe/Berlin"
    try {
      const details = {
        open: false,
        dataset: { publicGalleryDay: "2026-05-10" },
      }
      const el = {
        querySelector: () => null,
        querySelectorAll: () => [details],
      }
      const photo = { taken_at: "2026-05-10T00:30:00", day_key: "2026-05-10" }
      showGallery(el, [photo], ownerZone)
      assert.deepEqual(details.publicPhotos, [photo])
    } finally {
      if (previous === undefined) delete process.env.TZ
      else process.env.TZ = previous
    }
  })
}

test("trip maps cap photo markers at 100 while day galleries retain later photos and teardown clears every image", async () => {
  const previous = globalThis.document
  globalThis.document = {
    createElement() {
      return {
        style: {},
        removeAttribute(name) {
          delete this[name]
        },
      }
    },
  }
  try {
    const lib = library()
    const { instance, events } = setup(async () => lib)
    const gallery = {
      images: [],
      append(image) {
        this.images.push(image)
      },
      replaceChildren() {
        this.images = []
      },
    }
    const details = {
      open: false,
      dataset: { publicGalleryDay: "2026-05-10" },
      querySelector: () => gallery,
    }
    instance.el.querySelectorAll = (selector) =>
      selector.includes("details")
        ? [details]
        : selector.includes("img")
          ? gallery.images
          : [gallery]
    const photos = Array.from({ length: 101 }, (_, id) => ({
      id: `photo-${id}`,
      latitude: 51,
      longitude: 12,
      day_key: "2026-05-10",
      thumbnail_url: `/api/v1/shared/synthetic/photos/${id}/thumbnail`,
    }))
    await events.get("public-share-snapshot")({ ...snapshot, photos })
    assert.equal(details.publicPhotos.length, 101)
    assert.equal(details.publicPhotos[100].id, "photo-100")
    const markers = lib.markers.filter((marker) => marker.element)
    assert.equal(markers.length, 100)
    assert.deepEqual(
      markers.map((marker) => marker.element.src),
      photos.slice(0, 100).map((photo) => photo.thumbnail_url),
    )
    details.open = true
    openGallery(details)
    const galleryImages = [...gallery.images]
    assert.equal(galleryImages.length, 101)
    assert.equal(galleryImages[100].src, photos[100].thumbnail_url)
    instance.disconnected()
    assert.equal(lib.maps[0].removed, 1)
    assert.ok(lib.markers.every((marker) => marker.removed))
    assert.ok(markers.every((marker) => marker.element.src === undefined))
    assert.ok(galleryImages.every((image) => image.src === undefined))
    assert.deepEqual(details.publicPhotos, [])
    assert.deepEqual(gallery.images, [])
    instance.destroyed()
    assert.equal(events.size, 0)
  } finally {
    if (previous) globalThis.document = previous
    else delete globalThis.document
  }
})
