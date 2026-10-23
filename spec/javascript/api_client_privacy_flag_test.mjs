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
    (c) => c.fetchVisitsPage(range),
    (c) => c.fetchPlacesPage(),
    (c) => c.fetchPhotos(range),
    (c) => c.fetchTracksPage(range),
    (c) => c.fetchTrackWithSegments(7),
    (c) => c.fetchTrackPointsPage(7),
    (c) => c.fetchTimeline(range),
  ])

  assert.equal(requests.length, 10)
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

test("privacy zones come back flattened with the fingerprint header", async () => {
  const originalFetch = globalThis.fetch
  globalThis.fetch = async () => ({
    ok: true,
    headers: {
      get: (name) => (name === "X-Privacy-Zones-Fingerprint" ? "abc" : null),
    },
    json: async () => [
      { radius_meters: 300, places: [{ latitude: 52.4, longitude: 13.5 }] },
    ],
  })
  try {
    const result = await new ApiClient("test-key").fetchPrivacyZones()

    assert.deepEqual(result, {
      zones: [{ lon: 13.5, lat: 52.4, radiusMeters: 300 }],
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
    })
  } finally {
    globalThis.fetch = originalFetch
  }
})
