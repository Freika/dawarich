import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const importAppModule = async (relativePath) =>
  import(
    `data:text/javascript;base64,${Buffer.from(
      await readFile(
        new URL(`../../app/javascript/${relativePath}`, import.meta.url),
        "utf8",
      ),
    ).toString("base64")}`
  )
const { LoadingCounter } = await importAppModule(
  "maps_maplibre/utils/loading_counter.js",
)
const { visitsToGeoJSON } = await importAppModule(
  "maps_maplibre/utils/visit_features.js",
)

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
  visitsToGeoJSON,
  LoadingCounter,
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

const centered = loader.visitsToGeoJSON([
  { id: 3, place: null, center: { latitude: 52.51, longitude: 13.41 } },
  { id: 4, place: null, center: { latitude: 0, longitude: 0 } },
  {
    id: 5,
    place: { name: "Chosen", latitude: 51, longitude: 12 },
    center: { latitude: 52.51, longitude: 13.41 },
  },
  { id: 6, place: null, center: null },
])
assert.deepEqual(
  JSON.parse(
    JSON.stringify(centered.features.map((f) => f.geometry.coordinates)),
  ),
  [
    [13.41, 52.51],
    [0, 0],
    [12, 51],
  ],
)
