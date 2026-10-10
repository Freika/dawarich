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
