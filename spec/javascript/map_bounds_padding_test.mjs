import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/map_padding.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { overlayAwarePadding } = await import(moduleUrl)

test("keeps fitted data clear of a left-edge map toolbar", () => {
  const padding = overlayAwarePadding(
    { left: 0, right: 1280, top: 100, bottom: 720, width: 1280 },
    { left: 12, right: 64, top: 112, bottom: 336 },
  )

  assert.deepEqual(padding, { top: 50, right: 50, bottom: 50, left: 76 })
})

test("uses base padding without a measurable toolbar", () => {
  assert.deepEqual(overlayAwarePadding(null, null), {
    top: 50,
    right: 50,
    bottom: 50,
    left: 50,
  })
})

test("measures toolbar clearance from a shifted map viewport", () => {
  const padding = overlayAwarePadding(
    { left: 480, right: 1280, top: 100, bottom: 720, width: 800 },
    { left: 492, right: 544, top: 112, bottom: 336 },
  )

  assert.equal(padding.left, 76)
})
