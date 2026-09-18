import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// clearLayerReferences() touches only `this.layers` and `this.eventHandlersSetup`,
// so it runs against a plain object — no map, no layer classes. Imports are
// stripped because the other methods reference them, but none of that executes
// here (same base64 data-URL technique as points_mvt_layer_test.mjs).
const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/layer_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(withoutImports).toString("base64")}`
const { LayerManager } = await import(moduleUrl)

function teardown(layers) {
  const context = { layers, eventHandlersSetup: true }
  LayerManager.prototype.clearLayerReferences.call(context)
  return context
}

test("releases the tile-error listener before orphaning the layers", () => {
  // The handler is registered on the map, not the style, so it survives
  // setStyle: unreleased, it leaks once per theme change and the replacement
  // layer adds another, so one failure toasts once per style change.
  let unwatched = 0
  const context = teardown({
    pointsMvtLayer: {
      _unwatchTileErrors: () => {
        unwatched += 1
      },
    },
  })

  assert.equal(unwatched, 1)
  assert.deepEqual(context.layers, {})
})

test("releases the tracks-mvt map listeners before orphaning the layers", () => {
  // The error handler lives on the map and survives setStyle — unreleased,
  // each style change stacks another listener.
  const seen = []
  teardown({
    tracksMvtLayer: {
      _unwatchTileErrors: () => seen.push("errors"),
    },
  })

  assert.deepEqual(seen, ["errors"])
})

test("removes the fog layer before orphaning the layers", () => {
  // Fog's canvas and move/zoom/sourcedata listeners live on the map and
  // container — orphaning the object without remove() leaks them per style
  // change.
  let removed = 0
  teardown({
    fogLayer: {
      remove: () => {
        removed += 1
      },
    },
  })

  assert.equal(removed, 1)
})

test("removes visited-country listeners before orphaning the layer", () => {
  let removed = 0
  teardown({
    scratchLayer: {
      remove: () => {
        removed += 1
      },
    },
  })

  assert.equal(removed, 1)
})

test("unsubscribes every delegated map handler before rebuilding a style", () => {
  const seen = []
  const context = teardown({})
  context.eventHandlerCleanups = [
    () => seen.push("point-click"),
    () => seen.push("track-hover"),
  ]

  LayerManager.prototype.clearLayerReferences.call(context)

  assert.deepEqual(seen, ["point-click", "track-hover"])
  assert.deepEqual(context.eventHandlerCleanups, [])
})

test("tears down without any layers present", () => {
  assert.deepEqual(teardown({}).layers, {})
})
