import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const toDataUrl = (code) =>
  `data:text/javascript;base64,${Buffer.from(code).toString("base64")}`

const baseLayerSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/base_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const tracksLayerSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/tracks_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const { TracksLayer } = await import(
  toDataUrl(
    tracksLayerSource.replace(
      'import { BaseLayer } from "./base_layer"',
      `import { BaseLayer } from "${toDataUrl(baseLayerSource)}"`,
    ),
  )
)

function fakeMap(initialLayerIds) {
  const layers = initialLayerIds.map((id) => ({ id }))
  const sources = {}
  const indexOf = (id) => layers.findIndex((layer) => layer.id === id)
  const insert = (layer, beforeId) => {
    const at = beforeId ? indexOf(beforeId) : -1
    if (at === -1) layers.push(layer)
    else layers.splice(at, 0, layer)
  }
  return {
    order: () => layers.map((layer) => layer.id),
    getStyle: () => ({ layers: layers.map((layer) => ({ id: layer.id })) }),
    getLayer: (id) => layers.find((layer) => layer.id === id),
    addLayer: (config, beforeId) => insert({ id: config.id }, beforeId),
    moveLayer: (id, beforeId) => {
      const [layer] = layers.splice(indexOf(id), 1)
      insert(layer, beforeId)
    },
    removeLayer: (id) => layers.splice(indexOf(id), 1),
    getSource: (id) => sources[id],
    addSource: (id, spec) => {
      sources[id] = {
        ...spec,
        setData(data) {
          this.data = data
        },
      }
    },
    removeSource: (id) => delete sources[id],
    setPaintProperty: () => {},
    setLayoutProperty: (id, property, value) => {
      const layer = layers.find((candidate) => candidate.id === id)
      if (layer) layer[property] = value
    },
    setFilter: () => {},
    on: () => {},
    off: () => {},
    getZoom: () => 15,
    getCenter: () => ({ lng: 12.39, lat: 51.32 }),
    getCanvas: () => ({ style: {} }),
  }
}

function installAnimationStubs(t) {
  const original = {
    raf: globalThis.requestAnimationFrame,
    caf: globalThis.cancelAnimationFrame,
  }
  globalThis.requestAnimationFrame = () => 1
  globalThis.cancelAnimationFrame = () => {}
  t.after(() => {
    globalThis.requestAnimationFrame = original.raf
    globalThis.cancelAnimationFrame = original.caf
  })
}

const track = {
  type: "Feature",
  geometry: {
    type: "LineString",
    coordinates: [
      [12.37, 51.33],
      [12.38, 51.33],
      [12.38, 51.34],
      [12.39, 51.34],
    ],
  },
  properties: { id: 39, color: "#6366F1" },
}

function mountAfterBaseTracks(t) {
  installAnimationStubs(t)
  const map = fakeMap(["basemap"])
  const tracksLayer = new TracksLayer(map)
  tracksLayer.add({ type: "FeatureCollection", features: [] })
  map.addLayer({ id: "tracks-mvt" })
  map.addLayer({ id: "points-mvt" })
  return { map, tracksLayer }
}

test("the selection border sits above the base tile tracks once a track is selected", (t) => {
  const { map, tracksLayer } = mountAfterBaseTracks(t)

  tracksLayer.setSelectedTrack(track)

  const order = map.order()
  assert.ok(
    order.indexOf("tracks-selection-border") > order.indexOf("tracks-mvt"),
    `selection border must cover tracks-mvt, got ${order.join(" < ")}`,
  )
  assert.ok(
    order.indexOf("tracks-selection-flow") >
      order.indexOf("tracks-selection-border"),
  )
  assert.ok(
    order.indexOf("tracks-selection-flow") > order.indexOf("tracks-mvt"),
  )
})

test("segment highlighting keeps the whole selection above the base tile tracks", (t) => {
  const { map, tracksLayer } = mountAfterBaseTracks(t)

  tracksLayer.setSelectedTrack(track)
  tracksLayer.showSegments(track, [
    {
      mode: "walking",
      color: "#22C55E",
      coordinates: track.geometry.coordinates.slice(0, 2),
    },
    {
      mode: "walking",
      color: "#22C55E",
      coordinates: track.geometry.coordinates.slice(2),
    },
  ])

  const order = map.order()
  const base = order.indexOf("tracks-mvt")
  for (const id of [
    "tracks-selection-border",
    "tracks-segments",
    "tracks-selection-flow",
  ]) {
    assert.ok(
      order.indexOf(id) > base,
      `${id} must be above tracks-mvt, got ${order.join(" < ")}`,
    )
  }
})

test("selecting a track works when no tile tracks layer exists", (t) => {
  installAnimationStubs(t)
  const map = fakeMap(["basemap"])
  const tracksLayer = new TracksLayer(map)
  tracksLayer.add({ type: "FeatureCollection", features: [] })

  assert.doesNotThrow(() => tracksLayer.setSelectedTrack(track))
})

const walkingSegments = [
  {
    mode: "walking",
    color: "#22C55E",
    coordinates: track.geometry.coordinates.slice(0, 2),
  },
  {
    mode: "walking",
    color: "#22C55E",
    coordinates: track.geometry.coordinates.slice(2),
  },
]

test("reselecting without keeping segments hides them, so the opaque flow base never alternates with segment colours", (t) => {
  const { map, tracksLayer } = mountAfterBaseTracks(t)
  tracksLayer.setSelectedTrack(track)
  tracksLayer.showSegments(track, walkingSegments)

  tracksLayer.setSelectedTrack({ ...track, properties: { id: 40 } })

  assert.equal(tracksLayer.segmentsActive, false)
  assert.equal(map.getLayer("tracks-segments").visibility, "none")
})

test("reselecting while keeping segments leaves them visible", (t) => {
  const { map, tracksLayer } = mountAfterBaseTracks(t)
  tracksLayer.setSelectedTrack(track)
  tracksLayer.showSegments(track, walkingSegments)

  tracksLayer.setSelectedTrack(track, { preserveSegments: true })

  assert.equal(tracksLayer.segmentsActive, true)
  assert.notEqual(map.getLayer("tracks-segments").visibility, "none")
})

test("segment highlighting renders for a map-matched track whose display geometry is a MultiLineString", (t) => {
  const { map, tracksLayer } = mountAfterBaseTracks(t)
  const matchedTrack = {
    ...track,
    geometry: {
      type: "MultiLineString",
      coordinates: [track.geometry.coordinates],
    },
  }
  tracksLayer.setSelectedTrack(matchedTrack)

  tracksLayer.showSegments(matchedTrack, walkingSegments)

  assert.equal(tracksLayer.segmentsActive, true)
  assert.equal(map.getSource("tracks-segments-source").data.features.length, 2)
})
