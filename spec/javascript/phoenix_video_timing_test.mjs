import assert from "node:assert/strict"
import test from "node:test"
import {
  followCenter,
  lerpCamera,
} from "../../app-phoenix/assets/js/video/camera_path.js"
import { smoothSegmentCoords } from "../../app-phoenix/assets/js/video/path_smoothing.js"
import {
  buildRenderPlan,
  frameFraction,
} from "../../app-phoenix/assets/js/video/render_plan.js"
import {
  buildRouteClock,
  timeAtFraction,
} from "../../app-phoenix/assets/js/video/route_clock.js"
import {
  buildRouteTimeline,
  sliceAtFraction,
  sliceWindow,
} from "../../app-phoenix/assets/js/video/route_timeline.js"
import {
  buildStatRows,
  computeTrackStats,
  formatDistance,
  formatDuration,
  formatSpeed,
} from "../../app-phoenix/assets/js/video/video_stats.js"

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
  const { entries } = buildRouteTimeline(
    collection([
      lineString(MORNING, { start_at: "2026-08-20T08:00:00Z" }),
      lineString(EVENING, {}),
    ]),
  )

  assert.deepEqual(entries[0].coord, MORNING[0])
  assert.deepEqual(entries[entries.length - 1].coord, EVENING[1])
})

test("animates both sides of an antimeridian MultiLineString without joining them", () => {
  const western = [
    [179.8, 10],
    [179.9, 10],
  ]
  const eastern = [
    [-179.9, 10],
    [-179.8, 10],
  ]
  const { entries } = buildRouteTimeline(
    collection([
      {
        type: "Feature",
        properties: { startTime: 1_787_212_800 },
        geometry: { type: "MultiLineString", coordinates: [western, eastern] },
      },
    ]),
  )

  assert.deepEqual(
    entries.map(({ coord }) => coord),
    [...western, ...eastern],
  )
  assert.equal(entries[1].seg + 1, entries[2].seg)
})

test("render plan frame timestamps and outro preserve source duration", () => {
  const plan = buildRenderPlan({ durationSec: 15, fps: 30 })
  assert.deepEqual(plan, {
    fps: 30,
    totalFrames: 450,
    introFrames: 18,
    outroFrames: 90,
  })
  assert.equal(plan.totalFrames / plan.fps, 15)
  assert.equal(frameFraction(plan, 0), 0)
  assert.equal(frameFraction(plan, 17), 0)
  assert.ok(frameFraction(plan, 18) >= 0)
  assert.ok(frameFraction(plan, 359) < 1)
  assert.ok(
    Math.abs(frameFraction(plan, 75) - (1 - Math.cos(Math.PI / 6)) / 2) < 1e-12,
  )
  assert.equal(frameFraction(plan, 360), 1)
  assert.equal(frameFraction(plan, 449), 1)
  assert.equal(frameFraction(plan, 5000), 1)

  const short = buildRenderPlan({ durationSec: 3, fps: 30 })
  assert.deepEqual(short, {
    fps: 30,
    totalFrames: 90,
    introFrames: 14,
    outroFrames: 74,
  })
  assert.ok(short.introFrames + short.outroFrames < short.totalFrames)
})

const timed = (lat, lon, time) => ({ lat, lon, time })

test("clock respects recorded gaps and final HUD total", () => {
  const points = [
    timed(51.3402, 12.3712, "2026-08-20T08:00:00Z"),
    timed(51.3402, 12.376, "2026-08-20T08:10:00Z"),
    timed(51.3402, 12.39, "2026-08-20T11:00:00Z"),
    timed(51.3402, 12.395, "2026-08-20T11:10:00Z"),
  ]
  const clock = buildRouteClock(points)
  const stats = computeTrackStats(points)
  assert.equal(clock.entries[2].dist, clock.entries[1].dist)
  assert.equal(clock.totalDistance, stats.distanceM)
  assert.equal(clock.startTs, Date.parse("2026-08-20T08:00:00Z"))
  assert.equal(timeAtFraction(clock, 1), Date.parse("2026-08-20T11:10:00Z"))
  assert.equal(timeAtFraction(clock, 0), Date.parse("2026-08-20T08:00:00Z"))
  assert.equal(stats.movingTimeMs, 20 * 60 * 1000)
  assert.equal(buildRouteClock(points.slice(0, 1)), null)
  assert.deepEqual(buildRouteClock([...points].reverse()), clock)
})

test("stat rows format distance, duration and drop a meaningless speed", () => {
  assert.equal(formatDistance(850), "850 m")
  assert.equal(formatDistance(12_345), "12.3 km")
  assert.equal(formatDistance(16_093.44, "mi"), "10.0 mi")
  assert.equal(formatDuration(45_000), "45 s")
  assert.equal(formatDuration(3 * 3600 * 1000 + 5 * 60 * 1000), "3 h 5 min")
  assert.equal(formatSpeed(16.0934, "mi"), "10.0 mph")
  const rows = buildStatRows(
    { distanceM: 900, movingTimeMs: 3_600_000, avgSpeedKmh: 0.9 },
    "km",
    { distance: "Distanz", duration: "Dauer" },
  )
  assert.deepEqual(rows, [
    { label: "Distanz", value: "900 m" },
    { label: "Dauer", value: "1 h 0 min" },
  ])
})

test("follow camera trails the pen and the pull-out interpolates poses", () => {
  const timeline = buildRouteTimeline(collection([lineString(MORNING, {})]))
  const head = sliceAtFraction(timeline, 1).head
  assert.deepEqual(followCenter(timeline, 1, { windowM: 0 }), head)
  const center = followCenter(timeline, 1)
  assert.ok(center[0] < head[0])
  assert.deepEqual(
    lerpCamera({ center: [0, 0], zoom: 10 }, { center: [2, 4], zoom: 8 }, 0.5),
    { center: [1, 2], zoom: 9 },
  )
  assert.equal(sliceWindow(timeline, 10, 10).features.length, 0)
  assert.equal(smoothSegmentCoords(MORNING), MORNING)
})
