import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function loadModule(relativePath, dependencies = "") {
  const source = await readFile(new URL(relativePath, import.meta.url), "utf8")
  const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  const url = `data:text/javascript;base64,${Buffer.from(
    `${dependencies}\n${withoutImports}`,
  ).toString("base64")}`

  return import(url)
}

const { pointsToGeoJSON } = await loadModule(
  "../../app/javascript/maps_maplibre/utils/geojson_transformers.js",
)
const { EventHandlers } = await loadModule(
  "../../app/javascript/controllers/maps/maplibre/event_handlers.js",
  `
    const translate = (key) => key
    const formatTimestamp = (value) => String(value)
    const formatSpeed = (value) => String(value)
    const formatDistance = (value) => String(value)
    const escapeHtml = (value) => String(value)
  `,
)

function buildHandlers() {
  const handlers = Object.create(EventHandlers.prototype)
  handlers.controller = { settings: {}, timezoneValue: "UTC" }
  return handlers
}

// A clicked feature's geometry comes back snapped to the tile grid, so the
// popup must not read the position from it.
const tileSnapped = { coordinates: [12.3709, 51.3405] }

const apiPoint = {
  id: 7,
  timestamp: 0,
  latitude: 51.340299,
  longitude: 12.371235,
}

test("the real feature producer carries the stored coordinates", () => {
  const [feature] = pointsToGeoJSON([apiPoint]).features

  assert.equal(feature.properties.latitude, 51.340299)
  assert.equal(feature.properties.longitude, 12.371235)
})

test("a popup built from a real feature shows the stored position", () => {
  const [feature] = pointsToGeoJSON([apiPoint]).features
  const content = buildHandlers()._buildPointInfoContent(
    feature.properties,
    tileSnapped,
  )

  assert.match(content, /51\.340299, 12\.371235/)
  assert.doesNotMatch(content, /51\.340500/)
  assert.doesNotMatch(content, /12\.370900/)
})

test("coordinates render at six decimals so the text matches the points list", () => {
  const [feature] = pointsToGeoJSON([
    { id: 1, timestamp: 0, latitude: 51.25, longitude: 12.5 },
  ]).features
  const content = buildHandlers()._buildPointInfoContent(
    feature.properties,
    tileSnapped,
  )

  assert.match(content, /51\.250000, 12\.500000/)
})

test("a feature without stored coordinates falls back to the geometry", () => {
  const content = buildHandlers()._buildPointInfoContent(
    { id: 1, timestamp: 0 },
    tileSnapped,
  )

  assert.match(content, /51\.340500, 12\.370900/)
})

test("blank coordinate properties fall back rather than reading as zero", () => {
  const content = buildHandlers()._buildPointInfoContent(
    { id: 1, timestamp: 0, latitude: "", longitude: "" },
    tileSnapped,
  )

  assert.match(content, /51\.340500, 12\.370900/)
  assert.doesNotMatch(content, /0\.000000/)
})

test("coordinates are omitted when neither source has them", () => {
  const content = buildHandlers()._buildPointInfoContent(
    { id: 1, timestamp: 0 },
    undefined,
  )

  assert.doesNotMatch(content, /map_info\.coordinates/)
})
