import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/poster_studio/render/frame_geometry.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { frameBounds, frameCovers, longitudeWithin } = await import(moduleUrl)

test("latitude bounds follow the Mercator frame, not flat degrees", () => {
  const { south, north } = frameBounds(60, 5_000_000)

  assert.ok(Math.abs(south - 41.366) < 0.01, `south was ${south}`)
  assert.ok(Math.abs(north - 71.944) < 0.01, `north was ${north}`)
})

test("latitude bounds stay symmetric at small distances", () => {
  const { south, north } = frameBounds(52.52, 6000)

  assert.ok(Math.abs(52.52 - south - (north - 52.52)) < 0.001)
})

test("longitude comparison wraps across the antimeridian", () => {
  assert.equal(longitudeWithin(-179, 178, 4.7), true)
  assert.equal(longitudeWithin(170, 178, 4.7), false)
})

test("a frame wider than the world accepts every longitude", () => {
  assert.equal(longitudeWithin(-179, 0, 200), true)
})

test("frameCovers accepts a track just inside the rendered frame", () => {
  assert.equal(frameCovers([[10, 42]], 60, 10, 5_000_000), true)
})

test("frameCovers rejects a track north of the rendered frame", () => {
  assert.equal(frameCovers([[10, 73]], 60, 10, 5_000_000), false)
})
