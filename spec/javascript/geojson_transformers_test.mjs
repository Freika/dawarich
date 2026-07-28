import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const geometrySource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/geometry.js",
    import.meta.url,
  ),
  "utf8",
)
const transformersSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/geojson_transformers.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = transformersSource.replace(
  /^import[\s\S]*?from "[^"]+"\n/gm,
  "",
)
const combinedSource = `${geometrySource}\n${withoutImports}`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(combinedSource).toString("base64")}`
const { pointsToGeoJSON, simplifyPointsForRendering } = await import(moduleUrl)

function point(id, latitude, longitude, timestamp) {
  return { id, latitude, longitude, timestamp }
}

test("simplified point rendering keeps first point and drops nearby dense points", () => {
  const points = [
    point(1, 52.52, 13.405, 1_700_000_000),
    point(2, 52.52001, 13.40501, 1_700_000_010),
    point(3, 52.52002, 13.40502, 1_700_000_015),
    point(4, 52.521, 13.405, 1_700_000_016),
  ]

  assert.deepEqual(
    simplifyPointsForRendering(points).map((p) => p.id),
    [1, 4],
  )
})

test("simplified point rendering drops nearby points regardless of time gap", () => {
  const points = [
    point(1, 52.52, 13.405, 1_700_000_000),
    point(2, 52.52001, 13.40501, 1_700_086_400),
  ]

  assert.deepEqual(
    pointsToGeoJSON(points, { simplified: true }).features.map(
      (feature) => feature.properties.id,
    ),
    [1],
  )
})

test("simplified point rendering measures distance from the last kept point", () => {
  const points = [
    point(1, 52.52, 13.405, 1_700_000_000),
    point(2, 52.52027, 13.405, 1_700_000_010),
    point(3, 52.52054, 13.405, 1_700_000_020),
  ]

  assert.deepEqual(
    simplifyPointsForRendering(points).map((p) => p.id),
    [1, 3],
  )
})

test("raw point rendering keeps dense points", () => {
  const points = [
    point(1, 52.52, 13.405, 1_700_000_000),
    point(2, 52.52001, 13.40501, 1_700_000_010),
  ]

  assert.deepEqual(
    pointsToGeoJSON(points).features.map((feature) => feature.properties.id),
    [1, 2],
  )
})
