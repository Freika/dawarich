import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/layer_dependencies.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { anomaliesVisible } = await import(moduleUrl)

test("anomalies show when enabled and points are visible", () => {
  assert.equal(
    anomaliesVisible({ anomaliesEnabled: true, pointsVisible: true }),
    true,
  )
})

test("anomalies hide with the points layer", () => {
  assert.equal(
    anomaliesVisible({ anomaliesEnabled: true, pointsVisible: false }),
    false,
  )
})

test("anomalies stay hidden until enabled", () => {
  assert.equal(
    anomaliesVisible({ anomaliesEnabled: false, pointsVisible: true }),
    false,
  )
  assert.equal(anomaliesVisible(undefined), false)
})
