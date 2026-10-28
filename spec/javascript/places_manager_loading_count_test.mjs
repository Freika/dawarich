import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const currentDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(currentDir, "../..")
const filterSource = (
  await readFile(
    path.join(
      repoRoot,
      "app/javascript/controllers/maps/maplibre/places_tag_filters.js",
    ),
    "utf8",
  )
)
  .replace(/^import .*$/gm, "")
  .replace("export class PlacesTagFilters", "class PlacesTagFilters")
const sourcePath = path.join(
  repoRoot,
  "app/javascript/controllers/maps/maplibre/places_manager.js",
)
const source =
  filterSource +
  (await readFile(sourcePath, "utf8"))
    .replace(/^import .*$/gm, "")
    .replace("export class PlacesManager", "class PlacesManager")
    .concat("\nglobalThis.PlacesManager = PlacesManager\n")

const context = { console, SettingsManager: { updateSetting() {} } }
vm.createContext(context)
vm.runInContext(source, context)

function placeFeatures(id) {
  return ["boundary", "center"].map((featureKind) => ({
    properties: { id, featureKind },
  }))
}

test("the loading badge counts Places, not their boundary and center features", async () => {
  const placesLayer = { data: null, show() {} }
  const counts = []
  const manager = new context.PlacesManager({
    layerManager: { getLayer: () => placesLayer },
    api: {},
    dataLoader: {},
    settings: {},
    hasPlacesFiltersTarget: false,
    showProgress() {},
    updateLoadingCounts: ({ counts: loaded }) => counts.push(loaded.places),
  })
  manager.initializePlaceTagFilters = async () => {
    placesLayer.data = {
      type: "FeatureCollection",
      features: [...placeFeatures(1), ...placeFeatures(2)],
    }
  }

  await manager.togglePlaces({ target: { checked: true } })

  assert.equal(counts.at(-1), 2)
})
