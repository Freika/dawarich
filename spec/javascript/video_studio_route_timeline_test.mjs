import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// route_timeline reaches its dependencies through importmap bare specifiers,
// which Node cannot resolve — concatenate the sources with the imports
// stripped, the same approach video_studio_hud_overlay_test.mjs uses.
const read = (name) =>
  readFile(
    new URL(`../../app/javascript/video_studio/${name}.js`, import.meta.url),
    "utf8",
  )

const sources = await Promise.all(
  ["geo", "path_smoothing", "route_timeline"].map(read),
)
const bundle = sources
  .join("\n")
  .replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  .replace(/^export /gm, "")
  .concat("\nexport { buildRouteTimeline }\n")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(bundle).toString("base64")}`
const { buildRouteTimeline } = await import(moduleUrl)

// Leipzig, heading east through the day.
const MORNING = [
  [12.3712, 51.3402],
  [12.376, 51.3402],
]
const EVENING = [
  [12.39, 51.3402],
  [12.395, 51.3402],
]

const lineString = (coordinates, properties) => ({
  type: "Feature",
  properties,
  geometry: { type: "LineString", coordinates },
})

const collection = (features) => ({ type: "FeatureCollection", features })

test("draws chronologically when the tracks feed arrives newest-first", () => {
  // Tracks::IndexQuery orders start_at DESC, and Tracks::GeojsonSerializer
  // maps that order straight into the FeatureCollection.
  const { entries } = buildRouteTimeline(
    collection([
      lineString(EVENING, { start_at: "2026-08-20T18:00:00Z" }),
      lineString(MORNING, { start_at: "2026-08-20T08:00:00Z" }),
    ]),
  )

  assert.deepEqual(entries[0].coord, MORNING[0])
  assert.deepEqual(entries[entries.length - 1].coord, EVENING[1])
})

test("orders the routes feed by its unix-second startTime", () => {
  const { entries } = buildRouteTimeline(
    collection([
      lineString(EVENING, { startTime: 1_787_248_800 }),
      lineString(MORNING, { startTime: 1_787_212_800 }),
    ]),
  )

  assert.deepEqual(entries[0].coord, MORNING[0])
  assert.deepEqual(entries[entries.length - 1].coord, EVENING[1])
})

test("keeps the given order when a feature carries no start time", () => {
  // The trip page's pathData fallback builds a bare LineString with no
  // properties. A partially timed feed must not be reshuffled around the
  // features it cannot place — treating a missing time as 0 would drag them
  // to the front of the video.
  const { entries } = buildRouteTimeline(
    collection([
      lineString(MORNING, { start_at: "2026-08-20T08:00:00Z" }),
      lineString(EVENING, {}),
    ]),
  )

  assert.deepEqual(entries[0].coord, MORNING[0])
  assert.deepEqual(entries[entries.length - 1].coord, EVENING[1])
})
