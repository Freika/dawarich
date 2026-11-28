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

test("a single passing point has no stay draft", () => {
  assert.equal(pointsToVisitDraft([point(0)]), null)
})

test("two points thirty seconds apart have no stay draft", () => {
  assert.equal(pointsToVisitDraft([point(0), point(0.5)]), null)
})

test("the latest qualifying stay wins over a later drive-by point", () => {
  const draft = pointsToVisitDraft([
    point(0),
    point(1),
    point(60, 53),
    point(61, 53),
    point(120, 54),
  ])
  assert.equal(
    draft.startedAt,
    new Date(point(60).timestamp * 1000).toISOString(),
  )
  assert.equal(
    draft.endedAt,
    new Date(point(61).timestamp * 1000).toISOString(),
  )
  assert.equal(draft.lat, 53)
  assert.equal(draft.multipleStays, true)
})

test("the multiple-stays warning counts qualifying stays only", () => {
  const draft = pointsToVisitDraft([
    point(0),
    point(60),
    point(60.5),
    point(120),
    point(121),
  ])
  assert.equal(draft.multipleStays, false)
})

test("the user's merge threshold controls splitting including an exact boundary", () => {
  assert.equal(
    pointsToVisitDraft([point(0), point(1), point(21), point(22)], 20)
      .multipleStays,
    false,
  )
  assert.equal(
    pointsToVisitDraft([point(0), point(1), point(21), point(22)], 10)
      .multipleStays,
    true,
  )
})
