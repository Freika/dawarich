import assert from "node:assert/strict"
import { test } from "node:test"
import {
  DEFAULT_LAYOUT_ID,
  LAYOUT_CATEGORIES,
  layoutById,
  resolveLayoutGeometry,
} from "../../app-phoenix/assets/js/poster/data/layouts.js"
import {
  clampDpiToLimit,
  paperPixels,
  resolveExportGeometry,
  SAFE_FALLBACK_MAX_DIMENSION,
} from "../../app-phoenix/assets/js/poster/data/paper_sizes.js"
import {
  frameBounds,
  frameCovers,
  longitudeWithin,
} from "../../app-phoenix/assets/js/poster/render/frame_geometry.js"

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

test("paper orientation swaps physical pixels for landscape layouts", () => {
  assert.deepEqual(paperPixels("A4", 300), { width: 2480, height: 3508 })
  assert.deepEqual(paperPixels("A4", 300, { landscape: true }), {
    width: 3508,
    height: 2480,
  })
  const landscape = layoutById("print-a3-landscape")
  assert.equal(landscape.landscape, true)
  assert.equal(landscape.dimensionsLabel, "42 × 29.7 cm")
  assert.ok(landscape.aspect > 1)
  assert.deepEqual(
    resolveLayoutGeometry(landscape, 150, { maxDimensionPx: 16384 }),
    {
      width: 2480,
      height: 1754,
      requestedDpi: 150,
      effectiveDpi: 150,
      steppedDown: false,
      maxDimensionPx: 16384,
    },
  )
})

test("DPI steps down to the device cap and reports the effective DPI", () => {
  assert.equal(clampDpiToLimit("A0", 300, 8192), 175)
  const geometry = resolveExportGeometry("A0", 300, { maxDimensionPx: 8192 })
  assert.equal(geometry.effectiveDpi, 175)
  assert.equal(geometry.steppedDown, true)
  assert.ok(Math.max(geometry.width, geometry.height) <= 8192)
  assert.equal(
    resolveExportGeometry("A5", 300, { maxDimensionPx: 8192 }).steppedDown,
    false,
  )
  assert.equal(clampDpiToLimit("A0", 300, 1), 1)
})

test("pixel layouts keep exact size and scale down proportionally above the cap", () => {
  const story = layoutById("social-story")
  assert.deepEqual(
    resolveLayoutGeometry(story, 300, { maxDimensionPx: 8192 }),
    {
      width: 1080,
      height: 1920,
      requestedDpi: 0,
      effectiveDpi: 0,
      steppedDown: false,
      maxDimensionPx: 8192,
    },
  )
  const scaled = resolveLayoutGeometry(layoutById("wallpaper-4k"), 300, {
    maxDimensionPx: 1920,
  })
  assert.deepEqual(
    [scaled.width, scaled.height, scaled.steppedDown],
    [1920, 1080, true],
  )
})

test("unknown layout ids fall back to the default print layout", () => {
  assert.equal(layoutById("missing").id, DEFAULT_LAYOUT_ID)
  assert.deepEqual(
    LAYOUT_CATEGORIES.map((category) => category.id),
    ["print", "social", "wallpaper"],
  )
  assert.equal(SAFE_FALLBACK_MAX_DIMENSION, 8192)
})
