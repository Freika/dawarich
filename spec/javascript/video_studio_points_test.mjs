import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL("../../app/javascript/video_studio/points.js", import.meta.url),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { toVideoPoints } = await import(moduleUrl)

test("reads GeoJSON features from the map's point layers", () => {
  const points = toVideoPoints([
    {
      geometry: { coordinates: [13.4, 52.5] },
      properties: { timestamp: 1_700_000_000 },
    },
  ])

  assert.equal(points.length, 1)
  assert.equal(points[0].lat, 52.5)
  assert.equal(points[0].lon, 13.4)
  assert.equal(points[0].time, "2023-11-14T22:13:20.000Z")
})

test("reads raw points in both longitude/latitude and lon/lat shapes", () => {
  const points = toVideoPoints([
    { longitude: 13.4, latitude: 52.5, timestamp: 1_700_000_000 },
    { lon: 13.41, lat: 52.51, timestamp: 1_700_000_060 },
  ])

  assert.deepEqual(
    points.map((point) => point.lon),
    [13.4, 13.41],
  )
})

test("treats a large timestamp as milliseconds, a small one as seconds", () => {
  const [seconds, millis] = toVideoPoints([
    { lon: 0, lat: 0, timestamp: 1_700_000_000 },
    { lon: 0, lat: 0, timestamp: 1_700_000_000_000 },
  ])

  assert.equal(seconds.time, millis.time)
})

test("accepts an ISO timestamp string", () => {
  const [point] = toVideoPoints([
    { lon: 0, lat: 0, timestamp: "2026-06-14T08:41:00Z" },
  ])

  assert.equal(point.time, "2026-06-14T08:41:00.000Z")
})

test("accepts the decimal strings the points API actually returns", () => {
  const [point] = toVideoPoints([
    {
      id: 1,
      latitude: "51.3402",
      longitude: "12.3712",
      timestamp: 1_781_424_000,
    },
  ])

  assert.equal(point.lat, 51.3402)
  assert.equal(point.lon, 12.3712)
})

test("keeps timeless points so the distance still counts", () => {
  const [point] = toVideoPoints([{ lon: 13.4, lat: 52.5 }])

  assert.equal(point.time, null)
  assert.equal(point.lat, 52.5)
})

test("drops points with no usable coordinates", () => {
  const points = toVideoPoints([
    { timestamp: 1_700_000_000 },
    { lon: "west", lat: 52.5 },
    null,
  ])

  assert.deepEqual(points, [])
})

test("returns an empty list for anything that is not an array", () => {
  assert.deepEqual(toVideoPoints(undefined), [])
  assert.deepEqual(toVideoPoints({ points: [] }), [])
})
