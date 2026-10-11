import assert from "node:assert/strict"
import { test } from "node:test"
import { ReplayDayClock } from "../../app-phoenix/assets/js/map/replay/day_clock.js"
import { ReplayPhotoIndex } from "../../app-phoenix/assets/js/map/replay/photo_index.js"
import { stackLeftOffset } from "../../app-phoenix/assets/js/map/replay/photo_offset.js"
import {
  findTransportationEmoji,
  getCoordinates,
  parseTimestamp,
} from "../../app-phoenix/assets/js/map/replay/point_utils.js"

const at = (iso) => new Date(iso)

test("replay local clock preserves repeated-minute points and empty-minute gaps", () => {
  const clock = new ReplayDayClock("Europe/Berlin")
  const first = clock.minuteOfDay(at("2026-10-25T00:30:00Z"))
  const repeated = clock.minuteOfDay(at("2026-10-25T01:30:00Z"))

  assert.equal(first, 150)
  assert.equal(repeated, 210)
  assert.equal(clock.formatMinute("2026-10-25", first), "02:30 GMT+2")
  assert.equal(clock.formatMinute("2026-10-25", repeated), "02:30 GMT+1")
  assert.equal(clock.formatMinute("2026-10-25", 600), "09:00")

  const minutes = new Set([first, repeated])
  assert.equal(clock.nearestMinuteWithPoints(minutes, 170, 1500), 150)
  assert.equal(clock.nearestMinuteWithPoints(minutes, 180, 1500), 210)
  assert.equal(clock.nearestMinuteWithPoints(minutes, 900, 1500), 210)
  assert.equal(clock.nearestMinuteWithPoints(new Set(), 900, 1500), null)

  const density = clock.dataDensity([first, repeated], 1500, 50)
  assert.equal(density.filter((value) => value > 0).length, 2)
  assert.equal(density[5], 1)
  assert.equal(density[7], 1)
})

test("replay clock uses the profile zone, UTC default and DST day lengths", () => {
  assert.equal(
    new ReplayDayClock("America/Los_Angeles").minuteOfDay(
      at("2026-03-03T05:00:00Z"),
    ),
    21 * 60,
  )
  assert.equal(
    new ReplayDayClock().minuteOfDay(at("2026-03-03T05:00:00Z")),
    300,
  )
  const clock = new ReplayDayClock("Europe/Berlin")
  assert.equal(clock._getDayBounds("2026-03-29").length, 1380)
  assert.equal(clock._getDayBounds("2026-10-25").length, 1500)
  assert.equal(clock._getDayBounds("2026-06-01").length, 1440)
  assert.equal(clock.minuteOfDay(new Date(Number.NaN)), null)
})

test("photo index is deterministic across date change", () => {
  const photos = [
    {
      id: "b",
      taken_at: "2026-06-01T22:10:00Z",
      longitude: 13.4,
      latitude: 52.5,
    },
    {
      id: "a",
      taken_at: "2026-06-01T21:30:00Z",
      longitude: 13.4,
      latitude: 52.5,
    },
    { id: "c", taken_at: 1780351800, longitude: 13.4, latitude: 52.5 },
    { id: "skip", taken_at: "not a date", longitude: 13.4, latitude: 52.5 },
    { id: "nowhere", taken_at: "2026-06-01T10:00:00Z" },
  ]
  const build = () =>
    new ReplayPhotoIndex({ photos, timezone: "Europe/Berlin", getCoordinates })
  const index = build()

  assert.deepEqual(
    index.dayPhotos("2026-06-01").map((photo) => photo.id),
    ["a"],
  )
  assert.deepEqual(
    index.dayPhotos("2026-06-02").map((photo) => photo.id),
    ["b", "c"],
  )
  assert.deepEqual(
    index.idsToReveal("2026-06-02", Date.parse("2026-06-01T22:10:00Z")),
    ["b", "c"],
  )
  assert.deepEqual(
    index.idsToReveal("2026-06-01", Date.parse("2026-06-01T22:10:00Z")),
    ["a"],
  )
  assert.deepEqual(
    index.idsToReveal("2026-06-02", Date.parse("2026-06-01T22:00:00Z")),
    [],
  )
  assert.deepEqual(build().allPhotos(), index.allPhotos())
  assert.equal(
    new ReplayPhotoIndex({ photos: [], getCoordinates }).hasPhotos(),
    false,
  )
})

test("replay point helpers keep timestamp, coordinate and transport semantics", () => {
  assert.equal(
    parseTimestamp(1780351800).toISOString(),
    "2026-06-01T22:10:00.000Z",
  )
  assert.equal(
    parseTimestamp(1780351800000).toISOString(),
    "2026-06-01T22:10:00.000Z",
  )
  assert.equal(parseTimestamp(null), null)
  assert.deepEqual(
    getCoordinates({ geometry: { coordinates: ["13.4", "52.5"] } }),
    {
      lon: 13.4,
      lat: 52.5,
    },
  )
  assert.equal(getCoordinates({}), null)
  const tracks = {
    features: [
      {
        properties: {
          start_at: "2026-06-01T10:00:00Z",
          end_at: "2026-06-01T11:00:00Z",
          dominant_mode_emoji: "car",
          mode_timeline: [
            { start_time: 1780308000, end_time: 1780308600, emoji: "walk" },
          ],
        },
      },
    ],
  }
  assert.equal(
    findTransportationEmoji({ timestamp: 1780308300 }, tracks),
    "walk",
  )
  assert.equal(
    findTransportationEmoji({ timestamp: 1780309000 }, tracks),
    "walk",
  )
  assert.equal(findTransportationEmoji({ timestamp: "bad" }, tracks), null)
  assert.equal(findTransportationEmoji({ timestamp: 1780308300 }, null), null)
})

test("photo stack offset clears the visible cluster only", () => {
  const container = { left: 100 }
  assert.equal(stackLeftOffset({ container }), 16)
  assert.equal(
    stackLeftOffset({
      container,
      cluster: { width: 0, height: 10, right: 400 },
    }),
    16,
  )
  assert.equal(
    stackLeftOffset({
      container,
      cluster: { width: 40, height: 40, right: 160 },
    }),
    70,
  )
  assert.equal(
    stackLeftOffset({
      container,
      cluster: { width: 40, height: 40, right: 104 },
    }),
    16,
  )
})
