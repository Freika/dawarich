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
const { bulkPointsRequired, tiledPointsActive } = await import(moduleUrl)

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
