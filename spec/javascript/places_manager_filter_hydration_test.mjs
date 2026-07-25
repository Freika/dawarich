import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const currentDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(currentDir, "../..")
const sourcePath = path.join(
  repoRoot,
  "app/javascript/controllers/maps/maplibre/places_manager.js",
)
let source = await readFile(sourcePath, "utf8")
source = source
  .replace(/^import .*$/gm, "")
  .replace("export class PlacesManager", "class PlacesManager")
  .concat("\nglobalThis.PlacesManager = PlacesManager\n")

const checkboxes = [
  { value: "11", checked: false },
  { value: "12", checked: true },
  { value: "untagged", checked: false },
]
for (const checkbox of checkboxes) {
  checkbox.nextElementSibling = {
    style: { borderColor: "#123456" },
    classList: { add() {}, remove() {} },
  }
}
const context = {
  console,
  SettingsManager: { updateSetting() {} },
  document: {
    querySelectorAll: () => checkboxes,
  },
}
vm.createContext(context)
vm.runInContext(source, context)

const manager = new context.PlacesManager({
  layerManager: {},
  api: {},
  dataLoader: {},
  settings: { placesTagFilters: [11, "untagged"] },
})
await manager.restoreSavedTagFilters(manager.settings.placesTagFilters, {
  reloadPlaces: false,
})

assert.deepEqual(
  checkboxes.map((checkbox) => checkbox.checked),
  [true, false, true],
)

manager.settings.placesTagFilters = []
await manager.restoreSavedTagFilters([], { reloadPlaces: false })
assert.deepEqual(
  checkboxes.map((checkbox) => checkbox.checked),
  [false, false, false],
)

await manager.enableAllTagsInitial({ reloadPlaces: false })
assert.deepEqual(
  JSON.parse(JSON.stringify(manager.settings.placesTagFilters)),
  [11, 12, "untagged"],
)
