import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const baseLayerSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/base_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const anomaliesSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/anomalies_layer.js",
    import.meta.url,
  ),
  "utf8",
)

const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
// The layer imports translate/escapeHtml for popups — stub them for the harness.
const stubs = "const translate = (key) => key\nconst escapeHtml = (v) => v\n"
const combined =
  stubs + [baseLayerSource, anomaliesSource].map(stripImports).join("\n")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(combined).toString("base64")}`
const { AnomaliesLayer } = await import(moduleUrl)

function fakeMap() {
  const layers = []
  const sourceConfigs = new Map()
  const layerConfigs = []
  return {
    layers,
    sourceConfigs,
    layerConfigs,
    on() {},
    off() {},
    addSource(id, config) {
      sourceConfigs.set(id, config)
    },
    removeSource(id) {
      sourceConfigs.delete(id)
    },
    getSource(id) {
      return sourceConfigs.has(id) ? {} : undefined
    },
    addLayer(config) {
      layers.push(config.id)
      layerConfigs.push(config)
    },
    removeLayer(id) {
      const index = layers.indexOf(id)
      if (index !== -1) layers.splice(index, 1)
    },
    getLayer(id) {
      return layers.includes(id) ? { id } : undefined
    },
    getStyle() {
      return { layers: layers.map((id) => ({ id })) }
    },
    setLayoutProperty() {},
  }
}

test("classic mode keeps the GeoJSON source", () => {
  const map = fakeMap()
  const layer = new AnomaliesLayer(map, {})
  layer.add({ type: "FeatureCollection", features: [] })

  assert.equal(map.sourceConfigs.get("anomalies-source").type, "geojson")
})

test("tiled mode builds a vector source over the anomalies endpoint with no raw api key", () => {
  const map = fakeMap()
  const layer = new AnomaliesLayer(map, {
    tiled: true,
    apiKey: "secret-key-123",
    startAt: "2024-01-01T00:00",
    endAt: "2024-12-31T23:59",
  })
  layer.add({ type: "FeatureCollection", features: [] })

  const source = map.sourceConfigs.get("anomalies-source")
  assert.equal(source.type, "vector")
  const url = source.tiles[0]
  assert.ok(url.startsWith("/api/v1/tiles/anomalies/{z}/{x}/{y}.mvt?"))
  assert.ok(url.includes("u="))
  assert.ok(!url.includes("secret-key-123"))

  const circle = map.layerConfigs.find((c) => c.id === "anomalies")
  assert.equal(circle["source-layer"], "points")
})

test("setTiled rebuilds the source in the other mode and keeps visibility", () => {
  const map = fakeMap()
  const layer = new AnomaliesLayer(map, { apiKey: "secret-key-123" })
  layer.add({ type: "FeatureCollection", features: [] })
  layer.show()

  layer.setTiled(true, {
    startAt: "2024-01-01T00:00",
    endAt: "2024-12-31T23:59",
  })

  assert.equal(map.sourceConfigs.get("anomalies-source").type, "vector")
  assert.equal(layer.visible, true)

  layer.setTiled(false)
  assert.equal(map.sourceConfigs.get("anomalies-source").type, "geojson")
})
