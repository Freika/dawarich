import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const currentDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(currentDir, "../..")
const layerPath = path.join(
  repoRoot,
  "app/javascript/maps_maplibre/layers/places_layer.js",
)

class BaseLayer {
  constructor(map, options = {}) {
    this.map = map
    this.id = options.id
    this.sourceId = `${this.id}-source`
    this.visible = options.visible !== false
  }

  hide() {
    this.visible = false
    this.setVisibility(false)
  }
}

function recordingMap() {
  const visibility = {}
  return {
    visibility,
    getLayer: () => true,
    setLayoutProperty: (layerId, _property, value) => {
      visibility[layerId] = value
    },
  }
}

const context = { BaseLayer }
vm.createContext(context)
const source = (await readFile(layerPath, "utf8"))
  .replace(/^import .*\n/gm, "")
  .replace("export class PlacesLayer", "class PlacesLayer")
  .concat("\nglobalThis.PlacesLayer = PlacesLayer\n")
vm.runInContext(source, context)

test("Places layer renders the Visit Radius boundary and center together", () => {
  const layer = new context.PlacesLayer({})
  const configs = layer.getLayerConfigs()

  assert.deepEqual(JSON.parse(JSON.stringify(configs.map(({ id }) => id))), [
    "places-radius-fill",
    "places-radius-outline",
    "places",
    "places-labels",
  ])
  assert.equal(configs[0].type, "fill")
  assert.equal(configs[1].type, "line")
  assert.equal(configs[2].type, "circle")
})

test("Place boundaries stay hidden until the boundaries toggle is on", () => {
  const map = recordingMap()
  const layer = new context.PlacesLayer(map)

  layer.setVisibility(true)
  assert.equal(map.visibility["places-radius-fill"], "none")
  assert.equal(map.visibility["places-radius-outline"], "none")
  assert.equal(map.visibility.places, "visible")
  assert.equal(map.visibility["places-labels"], "visible")

  layer.setBoundariesVisible(true)
  assert.equal(map.visibility["places-radius-fill"], "visible")
  assert.equal(map.visibility["places-radius-outline"], "visible")

  layer.hide()
  assert.equal(map.visibility["places-radius-fill"], "none")
  assert.equal(map.visibility.places, "none")
})

test("Place boundaries follow the saved toggle on first render", () => {
  const map = recordingMap()
  const layer = new context.PlacesLayer(map, { boundariesVisible: true })

  layer.setVisibility(true)
  assert.equal(map.visibility["places-radius-fill"], "visible")
})
