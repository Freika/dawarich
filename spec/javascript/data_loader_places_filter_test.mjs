import assert from "node:assert/strict"
import { DataLoader } from "controllers/maps/maplibre/data_loader"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

const requests = []
globalThis.fetch = async (_url, options = {}) => {
  requests.push(options)
  return {
    ok: true,
    json: async () => ({
      settings: {
        enabled_map_layers: ["Places"],
        places_tag_filters: [11, "untagged"],
      },
    }),
  }
}

SettingsManager.initialize("test-key")
const settings = await SettingsManager.sync()
assert.deepEqual(JSON.parse(JSON.stringify(settings.placesTagFilters)), [
  11,
  "untagged",
])

await SettingsManager.updateSetting("placesTagFilters", [12])
const savedSettings = JSON.parse(requests.at(-1).body).settings
assert.deepEqual(savedSettings.places_tag_filters, [12])

const calls = []
const api = {
  fetchPlaces: async (options) => {
    calls.push(options)
    return []
  },
}
await SettingsManager.updateSetting("pointsVisible", false)
settings.pointsVisible = false
settings.placesEnabled = true

const loader = new DataLoader(api, "test-key", settings)
await loader.fetchMapData("2026-06-01", "2026-06-30")

assert.deepEqual(JSON.parse(JSON.stringify(calls)), [{ tag_ids: [12] }])

settings.placesTagFilters = []
calls.length = 0
const emptyLoader = new DataLoader(api, "test-key", settings)
await emptyLoader.fetchMapData("2026-06-01", "2026-06-30")
assert.deepEqual(calls, [])

const placeFeatures = loader.placesToGeoJSON([
  {
    id: 7,
    name: "Home",
    latitude: "52.52",
    longitude: "13.405",
    visit_radius: 125,
    tags: [{ color: "#123456" }],
  },
]).features
assert.equal(placeFeatures.length, 2)
assert.deepEqual(
  JSON.parse(
    JSON.stringify(placeFeatures.map((feature) => feature.geometry.type)),
  ),
  ["Polygon", "Point"],
)
assert.deepEqual(
  JSON.parse(
    JSON.stringify(
      placeFeatures.map((feature) => feature.properties.featureKind),
    ),
  ),
  ["boundary", "center"],
)
assert.ok(
  placeFeatures.every((feature) => feature.properties.visitRadius === 125),
)
