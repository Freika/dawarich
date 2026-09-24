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
  { id: 1, tracker_id: "phone", timestamp: 100 },
  { id: 2, tracker_id: "watch", timestamp: 100 },
  { id: 3, tracker_id: "phone", timestamp: 100 },
  { id: 4, tracker_id: null, timestamp: 100 },
  { id: 5, tracker_id: "", timestamp: 100 },
]

test("keeps only the points of the chosen devices", () => {
  assert.deepEqual(
    pointsFromDevice(points, [
      { tracker_id: "phone", start_at: 100, end_at: 100 },
    ]).map((point) => point.id),
    [1, 3],
  )
})

test("treats a missing and an empty device alike", () => {
  assert.deepEqual(
    pointsFromDevice(points, [
      { tracker_id: "", start_at: 100, end_at: 100 },
    ]).map((point) => point.id),
    [4, 5],
  )
})

test("keeps every point when no device is named", () => {
  assert.deepEqual(
    pointsFromDevice(points, []).map((point) => point.id),
    [1, 2, 3, 4, 5],
  )
})

test("retains both device handoff remainders without duplicating the shared timestamp", () => {
  const recording = [
    { id: 1, tracker_id: "phone", timestamp: 100 },
    { id: 2, tracker_id: "phone", timestamp: 200 },
    { id: 3, tracker_id: "watch", timestamp: 200 },
    { id: 4, tracker_id: "watch", timestamp: 300 },
  ]
  assert.deepEqual(
    pointsFromDevice(recording, [
      { tracker_id: "phone", start_at: 100, end_at: 200 },
      { tracker_id: "watch", start_at: 201, end_at: 300 },
    ]).map((point) => point.id),
    [1, 2, 4],
  )
})

test("preserves the lower priority device outside the overlapping window", () => {
  const recording = [
    { id: 1, tracker_id: "watch", timestamp: "100" },
    { id: 2, tracker_id: "watch", timestamp: "200" },
    { id: 3, tracker_id: "phone", timestamp: "200" },
    { id: 4, tracker_id: "phone", timestamp: "300" },
    { id: 5, tracker_id: "watch", timestamp: "400" },
  ]
  assert.deepEqual(
    pointsFromDevice(recording, [
      { tracker_id: "watch", start_at: 100, end_at: 199 },
      { tracker_id: "phone", start_at: 200, end_at: 300 },
      { tracker_id: "watch", start_at: 301, end_at: 400 },
    ]).map((point) => point.id),
    [1, 3, 4, 5],
  )
})
