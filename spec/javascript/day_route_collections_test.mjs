import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const segmenterUrl = moduleUrl(
  await read("maps_maplibre/utils/route_segmenter.js"),
)
const collections = await import(
  moduleUrl(
    `import { RouteSegmenter } from "${segmenterUrl}"\n${stripImports(await read("maps_maplibre/utils/day_route_collections.js"))}`,
  )
)
const pointsByDay = {
  "2026-01-02": [
    { longitude: 13.1, latitude: 52.1, timestamp: 1767351600 },
    { longitude: 13.2, latitude: 52.2, timestamp: 1767351900 },
  ],
  "2026-01-01": [
    { longitude: 13.0, latitude: 52.0, timestamp: 1767261600 },
    { longitude: 13.01, latitude: 52.01, timestamp: 1767261900 },
    { longitude: 13.02, latitude: 52.02, timestamp: 1767262200 },
  ],
  "2026-01-03": [{ longitude: 14, latitude: 53, timestamp: 1767438000 }],
}

test("builds one coloured route collection per day with movement", () => {
  const built = collections.buildDayRouteCollections(pointsByDay, {
    timeThresholdMinutes: 60,
  })

  assert.deepEqual(
    built.map((collection) =>
      collection.features.map((feature) => [
        feature.properties.dayKey,
        feature.properties.color,
        feature.geometry.coordinates.length,
      ]),
    ),
    [[["2026-01-01", "#6366F1", 3]], [["2026-01-02", "#F43F5E", 2]]],
  )
})

test("colours days from the fixed palette, then evenly around the hue wheel", () => {
  assert.deepEqual(collections.generateDayPalette(3), [
    "#6366F1",
    "#F43F5E",
    "#10B981",
  ])
  const many = collections.generateDayPalette(20)
  assert.equal(many.length, 20)
  assert.equal(many[0], "hsl(0, 70%, 55%)")
  assert.equal(many[1], "hsl(18, 70%, 55%)")
})
