import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/realtime_date_filter.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { parseTimestamp, pointMatchesActiveDateRange } = await import(moduleUrl)

const secondsAt = (iso) => String(Math.floor(Date.parse(iso) / 1000))
const msAt = (iso) => Date.parse(iso)

const range = {
  startValue: "2026-07-21T00:00:00+00:00",
  endValue: "2026-07-21T23:59:00+00:00",
}

test("parseTimestamp scales epoch seconds to milliseconds", () => {
  assert.equal(parseTimestamp("1721520300"), 1721520300000)
  assert.equal(parseTimestamp(1721520300), 1721520300000)
})

test("parseTimestamp passes epoch milliseconds through unchanged", () => {
  assert.equal(parseTimestamp("1721520300000"), 1721520300000)
  assert.equal(parseTimestamp(1721520300000), 1721520300000)
})

test("parseTimestamp parses ISO strings with an offset", () => {
  assert.equal(
    parseTimestamp("2026-07-21T12:00:00+00:00"),
    Date.parse("2026-07-21T12:00:00+00:00"),
  )
})

test("parseTimestamp returns null for null, undefined, and empty input", () => {
  assert.equal(parseTimestamp(null), null)
  assert.equal(parseTimestamp(undefined), null)
  assert.equal(parseTimestamp(""), null)
  assert.equal(parseTimestamp("not-a-date"), null)
})

test("point inside the active range is kept", () => {
  assert.equal(
    pointMatchesActiveDateRange(secondsAt("2026-07-21T12:00:00Z"), range),
    true,
  )
})

test("point inside the active range is kept for millisecond timestamps", () => {
  assert.equal(
    pointMatchesActiveDateRange(msAt("2026-07-21T12:00:00Z"), range),
    true,
  )
})

test("point before the start of the range is dropped", () => {
  assert.equal(
    pointMatchesActiveDateRange(secondsAt("2026-07-20T23:00:00Z"), range),
    false,
  )
})

test("point after the end of the range is dropped", () => {
  assert.equal(
    pointMatchesActiveDateRange(secondsAt("2026-07-22T01:00:00Z"), range),
    false,
  )
})

test("point exactly on the start boundary is kept", () => {
  assert.equal(
    pointMatchesActiveDateRange(secondsAt("2026-07-21T00:00:00Z"), range),
    true,
  )
})

test("point exactly on the end boundary is kept", () => {
  assert.equal(
    pointMatchesActiveDateRange(secondsAt("2026-07-21T23:59:00Z"), range),
    true,
  )
})

test("point with an unparseable timestamp is dropped", () => {
  assert.equal(pointMatchesActiveDateRange("", range), false)
  assert.equal(pointMatchesActiveDateRange(null, range), false)
})

test("default today range keeps points recorded after local midnight", () => {
  const openEndedToday = { ...range, treatEndAsOpen: true }

  assert.equal(
    pointMatchesActiveDateRange(
      secondsAt("2026-07-22T00:05:00Z"),
      openEndedToday,
    ),
    true,
  )
})

test("an open-ended range would drop the after-midnight point when the end is enforced", () => {
  assert.equal(
    pointMatchesActiveDateRange(secondsAt("2026-07-22T00:05:00Z"), {
      ...range,
      treatEndAsOpen: false,
    }),
    false,
  )
})

test("open-ended range still drops points before the start", () => {
  assert.equal(
    pointMatchesActiveDateRange(secondsAt("2026-07-20T12:00:00Z"), {
      ...range,
      treatEndAsOpen: true,
    }),
    false,
  )
})
