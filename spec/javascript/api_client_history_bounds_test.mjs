import assert from "node:assert/strict"
import test from "node:test"

import { ApiClient } from "maps_maplibre/services/api_client"

test("history bounds request opts into robust bounds without affecting fog", async () => {
  const requests = []
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (url) => {
    requests.push(new URL(url, "http://localhost"))
    return { ok: true, json: async () => ({}) }
  }

  try {
    const client = new ApiClient("test-key", "42")
    await client.fetchHistoryBounds({
      start_at: "2024-06-01",
      end_at: "2024-06-30",
    })
    await client.fetchFogHexagons({
      start_at: "2024-06-01",
      end_at: "2024-06-30",
    })

    assert.equal(requests[0].pathname, "/api/v1/maps/hexagons/bounds")
    assert.equal(requests[0].searchParams.get("robust"), "true")
    assert.equal(requests[0].searchParams.get("import_id"), "42")
    assert.equal(requests[1].pathname, "/api/v1/maps/hexagons/fog")
    assert.equal(requests[1].searchParams.has("robust"), false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("focused Track forwards a requested date range", async () => {
  const requests = []
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (url) => {
    requests.push(new URL(url, "http://localhost"))
    return { ok: true, json: async () => ({ features: [] }) }
  }

  try {
    const client = new ApiClient("test-key")
    await client.fetchTrackWithSegments(7, {
      startAt: "2024-06-01T00:00+02:00",
      endAt: "2024-06-01T23:59+02:00",
    })
    await client.fetchTrackWithSegments(7)

    assert.equal(
      requests[0].searchParams.get("start_at"),
      "2024-06-01T00:00+02:00",
    )
    assert.equal(
      requests[0].searchParams.get("end_at"),
      "2024-06-01T23:59+02:00",
    )
    assert.equal(requests[1].searchParams.has("start_at"), false)
    assert.equal(requests[1].searchParams.has("end_at"), false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("focused Track and editor Points keep the selected import scope", async () => {
  const requests = []
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (url) => {
    requests.push(new URL(url, "http://localhost"))
    return {
      ok: true,
      json: async () => ({ features: [{ properties: { id: 7 } }] }),
      headers: { get: () => "1" },
    }
  }

  try {
    const client = new ApiClient("test-key", "42")
    await client.fetchTrackWithSegments(7)
    await client.fetchTrackPointsPage(7)

    assert.equal(requests[0].pathname, "/api/v1/tracks/7")
    assert.equal(requests[1].pathname, "/api/v1/tracks/7/points")
    assert.ok(
      requests.every(
        (request) => request.searchParams.get("import_id") === "42",
      ),
    )
  } finally {
    globalThis.fetch = originalFetch
  }
})
