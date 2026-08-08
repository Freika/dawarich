import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/event_handlers.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const dependencies = `
  const translate = (key) => key
  const formatTimestamp = (value) => String(value)
  const formatSpeed = (value) => String(value)
  const formatDistance = (value) => String(value)
  const escapeHtml = (value) => String(value)
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(
  `${dependencies}\n${withoutImports}`,
).toString("base64")}`
const { EventHandlers } = await import(moduleUrl)

function buildHandlers() {
  const handlers = Object.create(EventHandlers.prototype)
  handlers.controller = { settings: {}, timezoneValue: "UTC" }
  return handlers
}

// A clicked feature's geometry is snapped to the tile grid, so it disagrees
// with the value stored for the point. The properties carry the real one.
const storedLatitude = "51.340299"
const storedLongitude = "12.371235"
const quantizedGeometry = { coordinates: [12.3709, 51.3405] }

test("the popup shows the stored coordinates, not the tile-snapped ones", () => {
  const content = buildHandlers()._buildPointInfoContent(
    {
      id: 1,
      timestamp: 0,
      latitude: storedLatitude,
      longitude: storedLongitude,
    },
    quantizedGeometry,
  )

  assert.match(content, /51\.340299, 12\.371235/)
  assert.doesNotMatch(content, /51\.340500/)
  assert.doesNotMatch(content, /12\.370900/)
})

test("the popup formats to six decimals so the text matches the points list", () => {
  const content = buildHandlers()._buildPointInfoContent(
    { id: 1, timestamp: 0, latitude: "51.25", longitude: "12.5" },
    quantizedGeometry,
  )

  assert.match(content, /51\.250000, 12\.500000/)
})

test("the popup falls back to the geometry when properties carry no coordinates", () => {
  const content = buildHandlers()._buildPointInfoContent(
    { id: 1, timestamp: 0 },
    quantizedGeometry,
  )

  assert.match(content, /51\.340500, 12\.370900/)
})

test("the popup omits coordinates when neither source has them", () => {
  const content = buildHandlers()._buildPointInfoContent(
    { id: 1, timestamp: 0 },
    undefined,
  )

  assert.doesNotMatch(content, /map_info\.coordinates/)
})
