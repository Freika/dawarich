import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

let source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/scratch_layer.js",
    import.meta.url,
  ),
  "utf8",
)
source = source.replace(/^import .+\n/gm, "")
const dependencies = `
const maplibregl = { addProtocol() {} }
class Protocol { constructor() { this.tile = () => {} } }
class BaseLayer {
  constructor(map, options) { this.map = map; this.id = options.id; this.sourceId = this.id + "-source" }
}
`
const url = `data:text/javascript;base64,${Buffer.from(dependencies + source).toString("base64")}`
const { ScratchLayer, visitedCountryFilter } = await import(url)

test("visited-country filtering uses only canonical ISO-3 metadata", () => {
  assert.deepEqual(visitedCountryFilter(["DEU", "POL"]), [
    "in",
    ["get", "iso_a3"],
    ["literal", ["DEU", "POL"]],
  ])
})

test("the bundled country source overzooms a native maxzoom-8 PMTiles archive", () => {
  const layer = new ScratchLayer({}, {})

  assert.deepEqual(layer.getSourceConfig(), {
    type: "vector",
    url: "pmtiles:///maps/countries-v1.pmtiles",
    minzoom: 0,
    maxzoom: 8,
  })
  assert.ok(
    layer
      .getLayerConfigs()
      .every((config) => config["source-layer"] === "countries"),
  )
})

test("a failed PMTiles source episode is reported once and can use a fresh archive URL", () => {
  const handlers = new Map()
  const map = {
    on(name, handler) {
      handlers.set(name, handler)
    },
    off(name) {
      handlers.delete(name)
    },
  }
  let failures = 0
  const layer = new ScratchLayer(map, {
    onTileError: () => {
      failures += 1
    },
  })

  layer._watchTileErrors()
  handlers.get("error")({ sourceId: "scratch-source" })
  handlers.get("error")({ sourceId: "scratch-source" })
  assert.equal(failures, 1)

  layer._cacheBuster = 1
  assert.equal(
    layer.getSourceConfig().url,
    "pmtiles:///maps/countries-v1.pmtiles?_=1",
  )
  layer._unwatchTileErrors()
  assert.equal(handlers.has("error"), false)
})
