import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/device_points.js",
    import.meta.url,
  ),
  "utf8",
)
const { pointsFromDevice } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

const points = [
  { id: 1, tracker_id: "phone" },
  { id: 2, tracker_id: "watch" },
  { id: 3, tracker_id: "phone" },
  { id: 4, tracker_id: null },
  { id: 5, tracker_id: "" },
]

test("keeps only the points of the chosen devices", () => {
  assert.deepEqual(
    pointsFromDevice(points, ["phone"]).map((point) => point.id),
    [1, 3],
  )
  assert.deepEqual(
    pointsFromDevice(points, ["phone", "watch"]).map((point) => point.id),
    [1, 2, 3],
  )
})

test("treats a missing and an empty device alike", () => {
  assert.deepEqual(
    pointsFromDevice(points, [""]).map((point) => point.id),
    [4, 5],
  )
})

test("keeps every point when no device is named", () => {
  assert.deepEqual(
    pointsFromDevice(points, []).map((point) => point.id),
    [1, 2, 3, 4, 5],
  )
})
