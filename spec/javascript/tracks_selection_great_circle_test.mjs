import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const url = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`

const { TracksLayer } = await import(
  url(
    (await read("maps_maplibre/layers/tracks_layer.js"))
      .replace(
        '"./base_layer"',
        `"${url(await read("maps_maplibre/layers/base_layer.js"))}"`,
      )
      .replace(
        '"../utils/flight_arcs"',
        `"${url(await read("maps_maplibre/utils/flight_arcs.js"))}"`,
      ),
  )
)
globalThis.requestAnimationFrame = () => 1
globalThis.cancelAnimationFrame = () => {}

function fakeMap() {
  const sources = {}
  return {
    sources,
    getStyle: () => ({ layers: [] }),
    getLayer: () => undefined,
    addLayer: () => {},
    moveLayer: () => {},
    getSource: (id) => sources[id],
    addSource: (id, spec) => {
      sources[id] = {
        ...spec,
        setData(data) {
          this.data = data
        },
      }
    },
    setPaintProperty: () => {},
    setLayoutProperty: () => {},
    on: () => {},
    off: () => {},
    getZoom: () => 3,
  }
}

const select = (coordinates) => {
  const map = fakeMap()
  const layer = new TracksLayer(map)
  layer.add({ type: "FeatureCollection", features: [] })
  layer.setSelectedTrack({
    type: "Feature",
    properties: { id: 1 },
    geometry: { type: "LineString", coordinates },
  })
  return map.sources[layer.selectionSourceId].data.features[0].geometry
}

test("a sparse polar track is highlighted along its great circle", () => {
  const geometry = select([
    [160, 70],
    [-60, 70],
  ])
  const vertex =
    (Math.atan(
      Math.tan((70 * Math.PI) / 180) / Math.cos((70 * Math.PI) / 180),
    ) *
      180) /
    Math.PI
  const peak = Math.max(
    ...geometry.coordinates.flat(Infinity).filter((_, i) => i % 2 === 1),
  )

  assert.ok(Math.abs(peak - vertex) < 0.5, `peaks at ${peak}, vertex ${vertex}`)
})

test("a dense track is highlighted with its own coordinates", () => {
  const coordinates = [
    [13.4, 52.5],
    [13.401, 52.501],
  ]

  assert.deepEqual(select(coordinates), { type: "LineString", coordinates })
})
