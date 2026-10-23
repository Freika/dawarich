import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const segmenterUrl = moduleUrl(
  await read("maps_maplibre/utils/route_segmenter.js"),
)
const { RouteSegmenter } = await import(segmenterUrl)
const { buildDayRouteCollections } = await import(
  moduleUrl(
    `import { RouteSegmenter } from "${segmenterUrl}"\n${stripImports(await read("maps_maplibre/utils/day_route_collections.js"))}`,
  )
)

const zone = { lon: 13.5, lat: 52.444, radiusMeters: 500 }
const at = (longitude, latitude, minute) => ({
  longitude,
  latitude,
  timestamp: 1767261600 + minute * 60,
})
const lineCount = (points, privacyZones) =>
  RouteSegmenter.pointsToRoutes(points, { privacyZones }).features.length

test("a straight line across a zone is broken at the zone", () => {
  const points = [
    at(13.4, 52.444, 0),
    at(13.49, 52.444, 5),
    at(13.51, 52.444, 10),
    at(13.6, 52.444, 15),
  ]

  assert.equal(lineCount(points, [zone]), 2)
  assert.equal(lineCount(points, []), 1)
})

test("a line that passes the zone at a distance stays whole", () => {
  const points = [at(13.4, 52.46, 0), at(13.6, 52.46, 5)]

  assert.equal(lineCount(points, [zone]), 1)
})

test("a time gap still splits a line away from any zone", () => {
  const points = [
    at(13.4, 52.6, 0),
    at(13.41, 52.6, 5),
    at(13.42, 52.6, 200),
    at(13.43, 52.6, 205),
  ]

  assert.equal(lineCount(points, [zone]), 2)
})

test("trip day routes break at a zone", () => {
  const day = [
    at(13.4, 52.444, 0),
    at(13.49, 52.444, 5),
    at(13.51, 52.444, 10),
    at(13.6, 52.444, 15),
  ]

  const [routes] = buildDayRouteCollections(
    { "2026-01-01": day },
    { privacyZones: [zone] },
  )

  assert.equal(routes.features.length, 2)
})
