import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL("../../app/javascript/video_studio/date_range.js", import.meta.url),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const { calendarPresetRange } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

for (const [zone, now, start, end] of [
  ["Europe/Berlin", "2026-10-27T12:00:00Z", "2026-10-21", "2026-10-27"],
  ["America/Los_Angeles", "2026-10-28T01:00:00Z", "2026-10-21", "2026-10-27"],
  ["Europe/Berlin", "2026-10-28T01:00:00Z", "2026-10-22", "2026-10-28"],
  ["America/New_York", "2026-11-03T12:00:00Z", "2026-10-28", "2026-11-03"],
  ["Pacific/Auckland", "2026-01-02T00:00:00Z", "2025-12-27", "2026-01-02"],
]) {
  test(`Last 7 days includes seven owner calendar dates in ${zone} at ${now}`, () => {
    assert.deepEqual(calendarPresetRange("week", new Date(now), zone), {
      start: `${start}T00:00`,
      end: `${end}T23:59`,
    })
  })
}
