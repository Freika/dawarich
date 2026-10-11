import assert from "node:assert/strict"
import { test } from "node:test"
import { createTileFreshness } from "../../app-phoenix/assets/js/map/data/tile_freshness.js"
import { createBaseLayers } from "../../app-phoenix/assets/js/map/layers/tile_layers.js"

function fakeMap() {
  const sources = new Map(),
    layers = new Map(),
    listeners = new Map(),
    refreshes = []
  return {
    sources,
    layers,
    refreshes,
    addSource(id, data) {
      sources.set(id, data)
    },
    getSource(id) {
      return sources.get(id)
    },
    removeSource(id) {
      sources.delete(id)
    },
    addLayer(layer) {
      layers.set(layer.id, layer)
    },
    getLayer(id) {
      return layers.get(id)
    },
    removeLayer(id) {
      layers.delete(id)
    },
    getStyle() {
      return { layers: [...layers.values()] }
    },
    setLayoutProperty() {},
    setPaintProperty() {},
    setFilter(id, filter) {
      layers.get(id).filter = filter
    },
    getFilter(id) {
      return layers.get(id)?.filter
    },
    refreshTiles(id) {
      refreshes.push(id)
    },
    on(event, fn) {
      listeners.set(event, new Set([...(listeners.get(event) ?? []), fn]))
    },
    off(event, fn) {
      listeners.get(event)?.delete(fn)
    },
    emit(event) {
      for (const fn of listeners.get(event) ?? []) fn()
    },
    listenerCount() {
      return [...listeners.values()].reduce((n, s) => n + s.size, 0)
    },
  }
}

test("browsing never requests complete point history", () => {
  const map = fakeMap()
  let exactReads = 0
  const owner = createBaseLayers({
    map,
    config: { range: { importId: 42 }, tracksEnabled: true },
    reader: {
      pages() {
        exactReads++
      },
    },
  })
  owner.mount()
  assert.equal(exactReads, 0)
  assert.equal(map.sources.get("points-mvt-source").type, "vector")
  assert.match(
    map.sources.get("points-mvt-source").tiles[0],
    /native\/map\/data\/tiles\/points/,
  )
  assert.match(map.sources.get("tracks-mvt-source").tiles[0], /import_id=42/)
  owner.destroy()
  assert.equal(map.sources.size, 0)
})

test("tile epoch update refreshes sources once and style reload restores layers", () => {
  const map = fakeMap()
  const owner = createBaseLayers({
    map,
    config: { epoch: 1, tracksEnabled: true },
  })
  owner.mount()
  owner.update({ epoch: 2, tracksEnabled: true })
  owner.update({ epoch: 2, tracksEnabled: true })
  map.emit("render")
  assert.deepEqual(map.refreshes, ["points-mvt-source", "tracks-mvt-source"])
  map.sources.clear()
  map.layers.clear()
  map.emit("style.load")
  map.emit("style.load")
  assert.equal(map.sources.size, 2)
  assert.equal(map.layers.size, 3)
  owner.destroy()
  assert.equal(map.listenerCount(), 0)
  map.emit("style.load")
  assert.equal(map.sources.size, 0)
})

test("external tile host receives no account credential", () => {
  const fresh = createTileFreshness("https://app.example")
  fresh.bump("points")
  for (const hostile of [
    "https://evil.example/native/map/data/tiles/points/1/2/3",
    "//evil.example/native/map/data/tiles/points/1/2/3",
    "https://app.example@evil.example/native/map/data/tiles/points/1/2/3",
    "http://app.example/native/map/data/tiles/points/1/2/3",
  ]) {
    const value = fresh.transformRequest(hostile)
    assert.equal(value.credentials, "omit")
    assert.equal(value.headers, undefined)
    assert.equal(
      new URL(value.url, "https://app.example").searchParams.get("_"),
      null,
    )
  }
  const local = fresh.transformRequest("/native/map/data/tiles/points/1/2/3")
  assert.equal(local.credentials, "same-origin")
  assert.ok(new URL(local.url).searchParams.get("_"))
  const other = createTileFreshness("https://app.example")
  other.bump("points")
  assert.notEqual(other.transformRequest(local.url).url, local.url)
})

test("focused edit exclusions survive range and style replacement", () => {
  const map = fakeMap()
  const owner = createBaseLayers({ map, config: { tracksEnabled: true } })
  owner.mount()
  try {
    owner.edit({ trackId: 8, pointIds: [9] })
    assert.match(JSON.stringify(map.getFilter("points-mvt")), /9/)
    owner.update({ tracksEnabled: true, range: { startAt: "new" } })
    assert.match(JSON.stringify(map.getFilter("tracks-mvt")), /8/)
    map.sources.clear()
    map.layers.clear()
    map.emit("style.load")
    assert.match(JSON.stringify(map.getFilter("points-mvt")), /9/)
    owner.edit(null)
    assert.equal(map.getFilter("points-mvt"), null)
  } finally {
    owner.destroy()
  }
})

test("native point and track invalidations fetch fresh tiles after a paused style frame", () => {
  const map = fakeMap()
  let paused = true
  const fetched = []
  map.refreshTiles = (id) => {
    if (!paused) fetched.push(id)
  }
  const owner = createBaseLayers({ map, config: { tracksEnabled: true } })
  try {
    owner.mount()
    owner.points.refresh()
    owner.points.refresh()
    owner.tracks.refresh()
    assert.deepEqual(fetched, [])
    paused = false
    map.emit("render")
    assert.deepEqual(fetched.sort(), ["points-mvt-source", "tracks-mvt-source"])
    fetched.length = 0
    owner.points.refresh()
    owner.destroy()
    map.emit("render")
    assert.deepEqual(fetched, [])
  } finally {
    owner.destroy()
  }
})
