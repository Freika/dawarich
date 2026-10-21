import assert from "node:assert/strict"
import test from "node:test"
import { createStudioSource } from "../../app-phoenix/assets/js/map/data/studio_source.js"
import { haversineDistance } from "../../app-phoenix/assets/js/video/geo.js"
import { createVideoSource } from "../../app-phoenix/assets/js/video/source.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}

const TRACK = {
  type: "FeatureCollection",
  features: [
    {
      type: "Feature",
      properties: { start_at: "2026-08-20T08:00:00Z" },
      geometry: {
        type: "LineString",
        coordinates: [
          [12.3712, 51.3402],
          [12.376, 51.3402],
        ],
      },
    },
  ],
}

const state = (revision, startAt = "2026-08-20T00:00") => ({
  revision,
  title: "Leipzig loop",
  range: { startAt, endAt: "2026-08-20T23:59", timezone: "Europe/Berlin" },
})

test("reads the track only after the provider has loaded its points", async () => {
  const studio = createStudioSource({
    getState: () => state(1),
    readSnapshot: async (_state, { purpose }) => {
      assert.equal(purpose, "video")
      return {
        points: [
          {
            longitude: "12.3712",
            latitude: "51.3402",
            timestamp: 1_787_212_800,
          },
        ],
        geojson: TRACK,
      }
    },
  })
  const video = createVideoSource(studio)
  const { trackGeojson, points, range, revision } = await video.load()

  assert.equal(trackGeojson.features.length, 1)
  assert.equal(points.length, 1)
  assert.deepEqual(points[0], {
    lat: 51.3402,
    lon: 12.3712,
    time: "2026-08-20T08:00:00.000Z",
  })
  assert.equal(range.timezone, "Europe/Berlin")
  assert.equal(revision, 1)
})

test("an empty snapshot yields an empty track rather than a crash", async () => {
  const studio = createStudioSource({
    getState: () => state(1),
    readSnapshot: async () => ({ points: [] }),
  })
  const { trackGeojson, points } = await createVideoSource(studio).load()
  assert.deepEqual(trackGeojson, { type: "FeatureCollection", features: [] })
  assert.deepEqual(points, [])
})

test("video range change waits for the map revision before reloading", async () => {
  let current = state(1)
  const acknowledged = deferred()
  const reads = []
  const studio = createStudioSource({
    getState: () => current,
    readSnapshot: async (snapshotState) => {
      reads.push(snapshotState.range.startAt)
      return { points: [], geojson: TRACK }
    },
    applyDates: async (range) => {
      await acknowledged.promise
      current = state(2, range.startAt)
      return { revision: 2 }
    },
  })
  const video = createVideoSource(studio)
  const loading = video.applyDates({
    startAt: "2026-08-21T00:00",
    endAt: "2026-08-21T23:59",
  })
  await Promise.resolve()
  assert.deepEqual(reads, [])
  acknowledged.resolve()
  const loaded = await loading
  assert.deepEqual(reads, ["2026-08-21T00:00"])
  assert.equal(loaded.revision, 2)
})

test("a trip video source keeps its fixed range", async () => {
  const studio = createStudioSource({
    getState: () => state(1),
    readSnapshot: async () => ({ points: [], geojson: TRACK }),
    fixedRange: true,
  })
  const video = createVideoSource(studio)
  assert.equal(video.fixed, true)
  await assert.rejects(
    video.applyDates({
      startAt: "2026-01-01T00:00",
      endAt: "2026-01-02T00:00",
    }),
    /fixed/,
  )
})

test("destroying the video source drops a pending snapshot", async () => {
  const pending = deferred()
  const studio = createStudioSource({
    getState: () => state(1),
    readSnapshot: () => pending.promise,
  })
  const video = createVideoSource(studio)
  const loading = video.load()
  video.destroy()
  pending.resolve({ points: [], geojson: TRACK })
  await assert.rejects(loading, { name: "AbortError" })
})

test("haversine distance measures metres on the sphere", () => {
  assert.equal(haversineDistance(0, 0, 0, 0), 0)
  assert.equal(Math.round(haversineDistance(0, 0, 0, 1)), 111195)
})
