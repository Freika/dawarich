import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/visit_draft.js",
    import.meta.url,
  ),
  "utf8",
)
const { pointsToVisitDraft } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)
const point = (minute, latitude = 52, longitude = 13) => ({
  timestamp: 1700000000 + minute * 60,
  latitude,
  longitude,
})

test("one stay uses first and last timestamps in chronological order", () => {
  const draft = pointsToVisitDraft([point(10), point(0), point(5)], 15)
  assert.equal(draft.startedAt, new Date(1700000000000).toISOString())
  assert.equal(draft.endedAt, new Date(1700000600000).toISOString())
  assert.equal(draft.multipleStays, false)
})

test("two stays use the latest stay and report the warning", () => {
  const draft = pointsToVisitDraft(
    [point(0), point(5), point(60, 53), point(65, 53)],
    15,
  )
  assert.equal(draft.startedAt, new Date(1700003600000).toISOString())
  assert.equal(draft.lat, 53)
  assert.equal(draft.multipleStays, true)
})

test("median coordinates resist a location outlier", () => {
  const draft = pointsToVisitDraft(
    [point(0, 52, 13), point(1, 52.1, 13.1), point(2, 80, 170)],
    15,
  )
  assert.equal(draft.lat, 52.1)
  assert.equal(draft.lng, 13.1)
})

test("empty points have no draft", () => {
  assert.equal(pointsToVisitDraft([], 15), null)
})

test("the user's merge threshold controls splitting including an exact boundary", () => {
  assert.equal(
    pointsToVisitDraft([point(0), point(20)], 20).multipleStays,
    false,
  )
  assert.equal(
    pointsToVisitDraft([point(0), point(20)], 10).multipleStays,
    true,
  )
})
