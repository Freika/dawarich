import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const currentDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(currentDir, "../..")
const dataLoaderPath = path.join(
  repoRoot,
  "app/javascript/controllers/maps/maplibre/data_loader.js",
)
const settingsManagerPath = path.join(
  repoRoot,
  "app/javascript/maps_maplibre/utils/settings_manager.js",
)
let dataLoaderSource = await readFile(dataLoaderPath, "utf8")
dataLoaderSource = dataLoaderSource
  .replace(/^import .*$/gm, "")
  .replace("export class DataLoader", "class DataLoader")
  .concat("\nglobalThis.DataLoader = DataLoader\n")
let settingsManagerSource = await readFile(settingsManagerPath, "utf8")
settingsManagerSource = settingsManagerSource
  .replaceAll("export const ", "const ")
  .replace("export class SettingsManager", "class SettingsManager")
  .concat("\nglobalThis.SettingsManager = SettingsManager\n")

const requests = []
const context = {
  console,
  fetch: async (_url, options = {}) => {
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
  },
  performanceMonitor: { mark() {}, measure() {} },
  RoutesLayer: {
    pointsToRoutes: () => ({ type: "FeatureCollection", features: [] }),
  },
  pointsToGeoJSON: () => ({ type: "FeatureCollection", features: [] }),
  createCircle: () => null,
  applySpeedColors: (value) => value,
}
vm.createContext(context)
vm.runInContext(settingsManagerSource, context)
vm.runInContext(dataLoaderSource, context)

context.SettingsManager.initialize("test-key")
const settings = await context.SettingsManager.sync()
assert.deepEqual(JSON.parse(JSON.stringify(settings.placesTagFilters)), [
  11,
  "untagged",
])

await context.SettingsManager.updateSetting("placesTagFilters", [12])
const savedSettings = JSON.parse(requests.at(-1).body).settings
assert.deepEqual(savedSettings.places_tag_filters, [12])

const calls = []
const api = {
  fetchPlaces: async (options) => {
    calls.push(options)
    return []
  },
}
settings.pointsVisible = false
settings.routesVisible = false
settings.placesEnabled = true

const loader = new context.DataLoader(api, "test-key", settings)
await loader.fetchMapData("2026-06-01", "2026-06-30")

assert.deepEqual(JSON.parse(JSON.stringify(calls)), [
  { tag_ids: [11, "untagged"] },
])

settings.placesTagFilters = []
calls.length = 0
const emptyLoader = new context.DataLoader(api, "test-key", settings)
await emptyLoader.fetchMapData("2026-06-01", "2026-06-30")
assert.deepEqual(calls, [])
