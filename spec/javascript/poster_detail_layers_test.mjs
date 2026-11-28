import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/poster_studio/data/protomaps_schema.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { detailLayersOutOfRange } = await import(moduleUrl)

// The planet tiles carry no buildings or rail below zoom 11 (#3974).
test("flags enabled buildings below the zoom where tiles carry them", () => {
  assert.equal(detailLayersOutOfRange(9.4, new Set(["rail"])), true)
})

test("flags enabled railways below the zoom where tiles carry them", () => {
  assert.equal(detailLayersOutOfRange(10.9, new Set(["buildings"])), true)
})

test("stays quiet once the tiles carry the detail", () => {
  assert.equal(detailLayersOutOfRange(11, new Set()), false)
})

test("stays quiet when both detail layers are hidden", () => {
  assert.equal(detailLayersOutOfRange(6, new Set(["buildings", "rail"])), false)
})
