import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/settings_manager.js",
    import.meta.url,
  ),
  "utf8",
)

// The predicate is pure — extract just the two functions to avoid the
// module's SettingsManager fetch dependencies.
const start = source.indexOf("export function bulkPointsRequired")
const end = source.indexOf("export class SettingsManager")
const functions = source.slice(start, end)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(functions).toString("base64")}`
const { bulkPointsRequired, tiledPointsActive, tiledLayerModes } = await import(
  moduleUrl
)

test("with tiles requested, only Scratch map still forces the bulk download", () => {
  const tiled = { pointsTiledRendering: true }

  assert.equal(bulkPointsRequired({ ...tiled, routesVisible: true }), false)
  assert.equal(
    bulkPointsRequired({ ...tiled, fogEnabled: true, fogOfWarMode: "points" }),
    false,
  )
  assert.equal(bulkPointsRequired({ ...tiled, heatmapEnabled: true }), false)
  assert.equal(bulkPointsRequired({ ...tiled, scratchEnabled: true }), true)
})

test("classic mode still needs bulk for routes, fog, and heatmap", () => {
  assert.equal(bulkPointsRequired({ routesVisible: true }), true)
  // routesVisible defaults to visible — undefined must count as blocking
  assert.equal(bulkPointsRequired({}), true)
  assert.equal(
    bulkPointsRequired({
      routesVisible: false,
      fogEnabled: true,
      fogOfWarMode: "points",
    }),
    true,
  )
  assert.equal(
    bulkPointsRequired({ routesVisible: false, heatmapEnabled: true }),
    true,
  )
})

test("hexagon fog never blocks in either mode", () => {
  assert.equal(
    bulkPointsRequired({
      routesVisible: false,
      fogEnabled: true,
      fogOfWarMode: "hexagons",
    }),
    false,
  )
})

test("tiledPointsActive requires the toggle AND no remaining blocker", () => {
  assert.equal(
    tiledPointsActive({ pointsTiledRendering: true, routesVisible: true }),
    true,
  )
  assert.equal(
    tiledPointsActive({ pointsTiledRendering: true, scratchEnabled: true }),
    false,
  )
  assert.equal(tiledPointsActive({ routesVisible: false }), false)
})

test("tiledLayerModes re-points every tiled-aware layer for the ON direction", () => {
  const modes = tiledLayerModes({
    pointsTiledRendering: true,
    routesVisible: true,
    tracksEnabled: true,
    fogEnabled: true,
    fogOfWarMode: "points",
  })

  assert.equal(modes.tiled, true)
  assert.deepEqual(modes.tracksMvt, {
    tracksEnabled: true,
    routesVisible: true,
  })
  assert.equal(modes.classicRoutes, false)
  assert.equal(modes.classicTracks, false)
  assert.equal(modes.fogTiled, true)
  assert.equal(modes.pointsSourceKeepAlive, true)
})

test("tiledLayerModes restores classic renderers for the OFF direction", () => {
  const modes = tiledLayerModes({
    pointsTiledRendering: false,
    routesVisible: true,
    tracksEnabled: true,
    fogEnabled: true,
    fogOfWarMode: "points",
  })

  assert.equal(modes.tiled, false)
  assert.deepEqual(modes.tracksMvt, {
    tracksEnabled: false,
    routesVisible: false,
  })
  assert.equal(modes.classicRoutes, true)
  assert.equal(modes.classicTracks, true)
  assert.equal(modes.fogTiled, false)
  assert.equal(modes.pointsSourceKeepAlive, false)
})

test("hexagon fog never claims the tile source and fog-off releases keep-alive", () => {
  const hexagons = tiledLayerModes({
    pointsTiledRendering: true,
    routesVisible: false,
    fogEnabled: true,
    fogOfWarMode: "hexagons",
  })
  assert.equal(hexagons.fogTiled, false)
  assert.equal(hexagons.pointsSourceKeepAlive, false)

  const fogOff = tiledLayerModes({
    pointsTiledRendering: true,
    routesVisible: false,
    fogEnabled: false,
    fogOfWarMode: "points",
  })
  assert.equal(fogOff.fogTiled, true)
  assert.equal(fogOff.pointsSourceKeepAlive, false)
})
