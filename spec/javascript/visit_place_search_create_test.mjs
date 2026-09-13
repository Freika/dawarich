import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const currentDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(currentDir, "../..")
const componentPath = path.join(
  repoRoot,
  "app/javascript/maps_maplibre/components/visit_place_search.js",
)
const dispatched = []
const context = {
  clearTimeout() {},
  document: {
    createElement() {
      return {
        _text: "",
        set textContent(value) {
          this._text = String(value)
        },
        get innerHTML() {
          return this._text
        },
      }
    },
    dispatchEvent(event) {
      dispatched.push(event)
    },
  },
  CustomEvent: class CustomEvent {
    constructor(type, options) {
      this.type = type
      this.detail = options.detail
    }
  },
  translate: (key) => key,
}
vm.createContext(context)
const source = (await readFile(componentPath, "utf8"))
  .replace(/^import .*\n/gm, "")
  .replace("export class VisitPlaceSearch", "class VisitPlaceSearch")
  .concat("\nglobalThis.VisitPlaceSearch = VisitPlaceSearch\n")
vm.runInContext(source, context)

test("creating from a Visit opens the shared Place form with attachment context", () => {
  const search = new context.VisitPlaceSearch(42, 52.52, 13.405, {
    innerHTML: "results",
  })
  search.createPlace("Corner cafe")

  assert.equal(dispatched.length, 1)
  assert.equal(dispatched[0].type, "place:create")
  assert.deepEqual(JSON.parse(JSON.stringify(dispatched[0].detail)), {
    latitude: 52.52,
    longitude: 13.405,
    visitId: 42,
    name: "Corner cafe",
  })
  assert.equal(search.mount.innerHTML, "")
})

test("the Visit picker renders only canonical Place rows", () => {
  const search = new context.VisitPlaceSearch(42, 52.52, 13.405, {})
  search.list = {
    innerHTML: "",
    querySelectorAll: () => [],
    querySelector: () => null,
  }
  search.render(
    [{ id: 1, name: "Home", latitude: 52.52, longitude: 13.405 }],
    "Home",
  )

  assert.match(search.list.innerHTML, /data-select-place/)
  assert.doesNotMatch(search.list.innerHTML, /data-select-area/)
})
