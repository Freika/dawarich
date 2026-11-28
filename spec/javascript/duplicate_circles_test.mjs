import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const geometry = await read("maps_maplibre/utils/geometry.js")
const source = (await read("maps_maplibre/utils/duplicate_circles.js")).replace(
  /^import[\s\S]*?from "[^"]+"\n/gm,
  "",
)
const { duplicateCircles } = await import(
  `data:text/javascript;base64,${Buffer.from(`${geometry}\n${source}`).toString("base64")}`
)

const places = [
  { lat: 52.5, lon: 13.4, radius: 100, color: "#2563eb" },
  { lat: 52.5009, lon: 13.4, radius: 50, color: "#16a34a" },
]

test("draws one closed circle per place in its colour", () => {
  const { collection } = duplicateCircles(places)

  assert.equal(collection.features.length, 2)
  assert.deepEqual(
    collection.features.map((feature) => feature.properties.color),
    ["#2563eb", "#16a34a"],
  )
  const ring = collection.features[0].geometry.coordinates[0]
  assert.deepEqual(ring[0], ring.at(-1))
})

test("the bounds hold every circle whole", () => {
  const { bounds } = duplicateCircles(places)
  const [[west, south], [east, north]] = bounds

  // 100 m south of the first place and 50 m north of the second.
  assert.ok(south < 52.5 - 0.0008 && south > 52.5 - 0.001)
  assert.ok(north > 52.5009 + 0.0004 && north < 52.5009 + 0.0006)
  assert.ok(west < 13.4 && east > 13.4)
})
