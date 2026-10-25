import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/layer_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+";?\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(withoutImports).toString("base64")}`
const { LayerManager } = await import(moduleUrl)

function orderedMap(existing) {
  const order = [...existing]
  return {
    order,
    getLayer: (id) => order.includes(id),
    addLayer: (config) => order.push(config.id),
    moveLayer(id, beforeId) {
      order.splice(order.indexOf(id), 1)
      order.splice(order.indexOf(beforeId), 0, id)
    },
  }
}

test("draws Place boundaries below Visit markers", () => {
  const map = orderedMap(["tracks", "visits"])
  globalThis.PlacesLayer = class {
    constructor(layerMap) {
      this.map = layerMap
    }

    add() {
      for (const id of [
        "places-radius-fill",
        "places-radius-outline",
        "places",
        "places-labels",
      ]) {
        this.map.addLayer({ id })
      }
    }
  }
  const manager = { map, layers: {}, settings: {} }

  LayerManager.prototype._addPlacesLayer.call(manager, {})

  assert.deepEqual(map.order, [
    "tracks",
    "places-radius-fill",
    "places-radius-outline",
    "visits",
    "places",
    "places-labels",
  ])
})

test("does not open a Place from clicks inside its boundary fill", () => {
  const subscriptions = []
  const manager = {
    map: { on: (...args) => subscriptions.push(args.slice(0, 2)) },
    eventHandlersSetup: false,
    eventHandlerCleanups: [],
  }

  LayerManager.prototype.setupLayerEventHandlers.call(manager, {})

  assert.ok(
    subscriptions.some(
      ([event, layer]) =>
        event === "click" && layer === "places-radius-outline",
    ),
  )
  assert.ok(!subscriptions.some(([, layer]) => layer === "places-radius-fill"))
})
