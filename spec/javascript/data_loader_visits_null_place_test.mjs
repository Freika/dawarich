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
let dataLoaderSource = await readFile(dataLoaderPath, "utf8")
dataLoaderSource = dataLoaderSource
  .replace(/^import[\s\S]*?from "[^"]+";?\n/gm, "")
  .replace("export class DataLoader", "class DataLoader")
  .concat("\nglobalThis.DataLoader = DataLoader\n")

const context = {
  console,
  performanceMonitor: { mark() {}, measure() {} },
  RoutesLayer: {},
  pointsToGeoJSON: () => ({ type: "FeatureCollection", features: [] }),
  createCircle: () => [],
  applySpeedColors: (value) => value,
}
vm.createContext(context)
vm.runInContext(dataLoaderSource, context)

const loader = new context.DataLoader({}, "test-key", {})
const geojson = loader.visitsToGeoJSON([
  {
    id: 1,
    name: null,
    display_name: "Address only",
    place: null,
    status: "suggested",
  },
  {
    id: 2,
    name: null,
    display_name: "Coffee Shop",
    place: { name: "Coffee Shop", longitude: 13.405, latitude: 52.52 },
    status: "confirmed",
  },
])

assert.equal(geojson.features.length, 1)
assert.deepEqual(
  JSON.parse(JSON.stringify(geojson.features[0].geometry.coordinates)),
  [13.405, 52.52],
)
assert.equal(geojson.features[0].properties.name, "Coffee Shop")
