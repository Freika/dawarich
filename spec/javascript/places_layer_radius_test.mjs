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

  update(data) {
    this.data = data
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

class HtmlLabelManager {
  constructor() {
    this.features = []
    this.visible = true
  }

  sync(features) {
    this.features = features
  }

  setVisibility(visible) {
    this.visible = visible
  }

  setOpacity(resolver) {
    this.opacity = resolver
  }

  clear() {
    this.features = []
  }
}

const context = { BaseLayer, HtmlLabelManager }
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
  assert.equal(layer.labels.visible, true)

  layer.setBoundariesVisible(true)
  assert.equal(map.visibility["places-radius-fill"], "visible")
  assert.equal(map.visibility["places-radius-outline"], "visible")

  layer.hide()
  assert.equal(map.visibility["places-radius-fill"], "none")
  assert.equal(map.visibility.places, "none")
  assert.equal(layer.labels.visible, false)
})

test("Place boundaries follow the saved toggle on first render", () => {
  const map = recordingMap()
  const layer = new context.PlacesLayer(map, { boundariesVisible: true })

  layer.setVisibility(true)
  assert.equal(map.visibility["places-radius-fill"], "visible")
})

test("Place labels are drawn once per Place, at its center", () => {
  const layer = new context.PlacesLayer(recordingMap())
  const boundary = {
    type: "Feature",
    geometry: { type: "Polygon", coordinates: [[[13.4, 52.5]]] },
    properties: { id: 7, name: "Cafe", featureKind: "boundary" },
  }
  const center = {
    type: "Feature",
    geometry: { type: "Point", coordinates: [13.4, 52.5] },
    properties: { id: 7, name: "Cafe", featureKind: "center" },
  }

  layer.update({ type: "FeatureCollection", features: [boundary, center] })

  assert.deepEqual(
    JSON.parse(JSON.stringify(layer.labels.features)),
    JSON.parse(JSON.stringify([center])),
  )
})

function evaluate(expression, properties) {
  if (!Array.isArray(expression)) return expression
  const [operator, ...args] = expression
  const value = (arg) => evaluate(arg, properties)
  if (operator === "get") return properties[args[0]]
  if (operator === "==") return value(args[0]) === value(args[1])
  if (operator === "case")
    return value(args[0]) ? value(args[1]) : value(args[2])
  if (operator === "coalesce")
    return args.map(value).find((item) => item != null)
  throw new Error(`Unexpected expression: ${operator}`)
}

test("geofences have a highlighted boundary distinct from ordinary Visit Radius outlines", () => {
  const configs = new context.PlacesLayer(recordingMap()).getLayerConfigs()
  const outline = configs.find(({ id }) => id === "places-radius-outline")
  const ordinary = { geofence: false, color: "#123456" }
  const geofence = { ...ordinary, geofence: true }
  assert.notEqual(
    evaluate(outline.paint["line-color"], ordinary),
    evaluate(outline.paint["line-color"], geofence),
  )
  assert.ok(
    evaluate(outline.paint["line-width"], geofence) >
      evaluate(outline.paint["line-width"], ordinary),
  )
  assert.equal(evaluate(outline.paint["line-color"], ordinary), "#123456")
})

test("archived places have muted centers, boundaries and labels even with geofencing enabled", () => {
  const layer = new context.PlacesLayer(recordingMap())
  const archived = { archived: true, geofence: true, color: "#123456" }
  const active = { ...archived, archived: false }
  const configs = layer.getLayerConfigs()
  for (const [id, property] of [
    ["places", "circle-opacity"],
    ["places-radius-fill", "fill-opacity"],
    ["places-radius-outline", "line-opacity"],
  ]) {
    const config = configs.find((item) => item.id === id)
    assert.ok(
      evaluate(config.paint[property], archived) <
        evaluate(config.paint[property], active),
    )
  }
  assert.equal(evaluate(configs[1].paint["line-color"], archived), "#94a3b8")
  assert.equal(layer.labels.opacity({ properties: archived }), 0.5)
  assert.equal(layer.labels.opacity({ properties: active }), 1)
})
