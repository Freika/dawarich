import assert from "node:assert/strict"
import test from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

test("native host studio snapshots use current configured route thresholds", async () => {
  const f = fixture({
    revision: 1,
    routeOptions: { distanceThresholdMeters: 500, timeThresholdMinutes: 15 },
  })
  f.reader.pages = async () => [
    { latitude: 52, longitude: 13, timestamp: 100, tracker_id: "synthetic" },
    {
      latitude: 52.001,
      longitude: 13.001,
      timestamp: 1300,
      tracker_id: "synthetic",
    },
  ]
  await f.owner.mount()
  for (const purpose of ["poster", "video", "replay"]) {
    const split = await f.owner.source.snapshot({ purpose })
    assert.equal(split.geojson.features.length, 0)
  }
  await f.owner.update({
    ...f.owner.config,
    routeOptions: { distanceThresholdMeters: 500, timeThresholdMinutes: 30 },
  })
  const joined = await f.owner.source.snapshot({ purpose: "poster" })
  assert.equal(joined.geojson.features.length, 1)
  assert.equal(joined.geojson.features[0].properties.pointCount, 2)
  f.owner.destroy()
})

test("native replay snapshot survives same-range refresh and aborts with its root", async () => {
  const { createReader } = await import(
    "../../app-phoenix/assets/js/map/data/reader.js"
  )
  let finish, signal
  const reader = createReader({
    origin: "https://map.test",
    fetch: async (url, options) => {
      if (new URL(url).pathname.endsWith("/points")) {
        signal = options.signal
        return new Promise((resolve) => {
          finish = resolve
        })
      }
      return new Response(JSON.stringify({ point_count: 0 }), { status: 200 })
    },
  })
  const f = fixture({ revision: 1, liveEnabled: false }, { reader })
  const points = () =>
    new Response(
      JSON.stringify([
        { id: 7, latitude: 52, longitude: 13, timestamp: 1774861200 },
      ]),
      { headers: { "x-total-pages": "1" } },
    )
  try {
    await f.owner.mount()
    const snapshot = f.owner.source.snapshot({ purpose: "replay" }).then(
      (data) => ({ data }),
      (error) => ({ error }),
    )
    await f.owner.update({ ...f.owner.config, panel: "tools" })
    assert.equal(signal.aborted, false)
    finish(points())
    const result = await snapshot
    assert.equal(result.error, undefined)
    assert.equal(result.data.points[0].id, 7)
    const pending = f.owner.source.snapshot({ purpose: "replay" })
    f.owner.destroy()
    assert.equal(signal.aborted, true)
    finish(points())
    await assert.rejects(pending, { name: "AbortError" })
  } finally {
    finish?.(points())
    f.owner.destroy()
  }
})
