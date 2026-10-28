import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

let source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/services/api_client.js",
    import.meta.url,
  ),
  "utf8",
)
source = source.replace(/^import .*\n/gm, "")
const { ApiClient } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

async function requestedUrls(calls) {
  const requests = []
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (url) => {
    requests.push(new URL(url, "http://localhost"))
    return {
      ok: true,
      status: 200,
      headers: { get: () => "1" },
      json: async () => ({ type: "FeatureCollection", features: [] }),
    }
  }
  try {
    const client = new ApiClient("test-key")
    for (const call of calls) {
      try {
        await call(client)
      } catch {
        // only the requested URL matters here
      }
    }
  } finally {
    globalThis.fetch = originalFetch
  }
  return requests
}

const range = { start_at: "2024-06-01", end_at: "2024-06-30" }

test("every map read asks the server to mask privacy zones", async () => {
  const requests = await requestedUrls([
    (c) => c.fetchPoints(range),
    (c) => c.fetchFogHexagons(range),
    (c) => c.fetchHistoryBounds(range),
    (c) => c.fetchRangeStatistics(range),
    (c) => c.fetchVisitsPage(range),
    (c) => c.fetchPlacesPage(),
    (c) => c.fetchPhotos(range),
    (c) => c.fetchTracksPage(range),
    (c) => c.fetchTrackWithSegments(7),
    (c) => c.fetchTrackPointsPage(7),
    (c) => c.fetchTimeline(range),
  ])

  assert.equal(requests.length, 11)
  for (const url of requests) {
    assert.equal(
      url.searchParams.get("mask_privacy_zones"),
      "true",
      `${url.pathname} is missing the privacy flag`,
    )
  }
})

test("selection and editing reads see the real data", async () => {
  const requests = await requestedUrls([
    (c) =>
      c.fetchPointsInArea({
        ...range,
        min_longitude: 1,
        max_longitude: 2,
        min_latitude: 1,
        max_latitude: 2,
      }),
    (c) =>
      c.fetchVisitsInArea({
        ...range,
        sw_lat: 1,
        sw_lng: 1,
        ne_lat: 2,
        ne_lng: 2,
      }),
    (c) => c.fetchTrackWithSegments(7, { unmasked: true }),
    (c) => c.fetchTrackPointsPage(7, { unmasked: true }),
  ])

  assert.equal(requests.length, 4)
  for (const url of requests) {
    assert.equal(
      url.searchParams.has("mask_privacy_zones"),
      false,
      url.pathname,
    )
  }
})

test("an all-time area selection sends no date range", async () => {
  const requests = await requestedUrls([
    (c) =>
      c.fetchPointsInArea({
        min_longitude: 1,
        max_longitude: 2,
        min_latitude: 1,
        max_latitude: 2,
      }),
    (c) => c.fetchVisitsInArea({ sw_lat: 1, sw_lng: 1, ne_lat: 2, ne_lng: 2 }),
  ])

  assert.equal(requests.length, 2)
  for (const url of requests) {
    assert.equal(url.searchParams.has("start_at"), false, url.pathname)
    assert.equal(url.searchParams.has("end_at"), false, url.pathname)
  }
})

test("an area selection over the point cap reports it was truncated", async () => {
  const originalFetch = globalThis.fetch
  const respond = (totalPages) => async () => ({
    ok: true,
    headers: { get: (name) => (name === "X-Total-Pages" ? totalPages : null) },
    json: async () => [{ id: 1 }],
  })
  const bbox = {
    min_longitude: 1,
    max_longitude: 2,
    min_latitude: 1,
    max_latitude: 2,
  }
  try {
    const client = new ApiClient("test-key")
    globalThis.fetch = respond("3")
    assert.deepEqual(await client.fetchPointsInArea(bbox), {
      points: [{ id: 1 }],
      truncated: true,
    })
    globalThis.fetch = respond("1")
    assert.equal((await client.fetchPointsInArea(bbox)).truncated, false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("privacy zones come back as the shifted masked areas with the fingerprint header", async () => {
  const originalFetch = globalThis.fetch
  globalThis.fetch = async () => ({
    ok: true,
    headers: {
      get: (name) => (name === "X-Privacy-Zones-Fingerprint" ? "abc" : null),
    },
    json: async () => [
      {
        radius_meters: 300,
        places: [
          {
            latitude: 52.4,
            longitude: 13.5,
            masked_area: {
              latitude: 52.401,
              longitude: 13.502,
              radius_meters: 430,
            },
          },
        ],
      },
    ],
  })
  try {
    const result = await new ApiClient("test-key").fetchPrivacyZones()

    assert.deepEqual(result, {
      zones: [{ lon: 13.502, lat: 52.401, radiusMeters: 430 }],
      fingerprint: "abc",
    })
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("a failed zone request leaves the map without zones instead of failing", async () => {
  const originalFetch = globalThis.fetch
  globalThis.fetch = async () => {
    throw new Error("offline")
  }
  try {
    assert.deepEqual(await new ApiClient("test-key").fetchPrivacyZones(), {
      zones: [],
      fingerprint: null,
      failed: true,
    })
  } finally {
    globalThis.fetch = originalFetch
  }
})
