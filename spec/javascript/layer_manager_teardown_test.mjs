import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// Source assertion rather than instantiation: LayerManager pulls in ~20 layer
// modules, and the property under test is purely structural — that the
// map-level listeners are released before the layer references are dropped.
const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/layer_manager.js",
    import.meta.url,
  ),
  "utf8",
)

function clearLayerReferencesBody() {
  const start = source.indexOf("clearLayerReferences()")
  assert.ok(start !== -1, "clearLayerReferences() is gone — rename?")
  const orphan = source.indexOf("this.layers = {}", start)
  assert.ok(
    orphan !== -1,
    "clearLayerReferences() no longer orphans this.layers",
  )
  return source.slice(start, orphan)
}

test("releases the tile-error listener before orphaning the layers", () => {
  // The handler is registered on the map, not the style, so it survives
  // setStyle: without this the listener leaks once per theme change and the
  // replacement layer adds another.
  assert.match(
    clearLayerReferencesBody(),
    /pointsMvtLayer\?\._unwatchTileErrors\(\)/,
  )
})

test("disarms point dragging before orphaning the layers", () => {
  // Same class of map-level state, already guarded — pinned so a future edit
  // cannot quietly drop either teardown.
  assert.match(
    clearLayerReferencesBody(),
    /pointsLayer\?\.setEditMode\(false\)/,
  )
})
