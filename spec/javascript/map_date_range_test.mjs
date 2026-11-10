import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/maps/maplibre/date_range.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const stubs = `
  const anomaliesVisible = (settings) => settings.anomalies
  const SettingsManager = { getSettings: () => globalThis.__settings }
  const DateManager = {
    formatDateForAPI: (date) => "api:" + (date.getMonth() + 1) + "-" + date.getDate(),
    parseMonthSelector: (value) => ({ startDate: value + "-01", endDate: value + "-31" }),
  }
`
const { MapDateRange } = await import(
  `data:text/javascript;base64,${Buffer.from(stubs + source).toString("base64")}`
)

function mapController() {
  const calls = []
  const controller = {
    layerManager: {
      getLayer: (name) =>
        name === "map-editor" ? { close: () => calls.push("editor") } : null,
    },
    timelineBridge: { clearDayHighlight: () => calls.push("highlight") },
    loadMapData: async (options) => calls.push(["load", options]),
    layerVisibilityManager: {
      refreshAnomalies: () => calls.push("anomalies"),
    },
    refreshTimelineFeedIfActive: () => calls.push("feed"),
    familyManager: { debouncedLoadHistory: () => calls.push("family") },
  }
  return { controller, range: new MapDateRange(controller), calls }
}

const sideEffects = (fitBounds) => [
  "editor",
  "highlight",
  ["load", { fitBounds }],
  "anomalies",
  "feed",
  "family",
]

test("every date range change runs the same reload", async () => {
  globalThis.__settings = { anomalies: true }

  const month = mapController()
  await month.range.monthChanged({ target: { value: "2024-06" } })
  assert.equal(month.controller.startDateValue, "2024-06-01")
  assert.equal(month.controller.endDateValue, "2024-06-31")
  assert.deepEqual(month.calls, sideEffects(true))

  const timeline = mapController()
  await timeline.range.navigateTimelineDateRange({
    startAt: "2024-07-01T00:00",
    endAt: "2024-07-02T00:00",
    fitBounds: false,
  })
  assert.equal(timeline.controller.startDateValue, "api:7-1")
  assert.deepEqual(timeline.calls, sideEffects(false))

  const direct = mapController()
  await direct.range.setDateRange("2024-08-01T00:00", "2024-08-31T23:59")
  assert.equal(direct.controller.endDateValue, "2024-08-31T23:59")
  assert.deepEqual(direct.calls, sideEffects(true))
})

test("an invalid Timeline range leaves the map untouched", async () => {
  const { range, calls } = mapController()
  await range.navigateTimelineDateRange({ startAt: "nope", endAt: "x" })
  assert.deepEqual(calls, [])
})

test("realtime keeps the end open only on the untouched load-time range", () => {
  const { controller, range } = mapController()
  Object.assign(controller, {
    startDateValue: "a",
    endDateValue: "b",
    defaultDateRange: { startValue: "a", endValue: "b", reachesNow: true },
  })
  assert.equal(range.realtimeDateRange().treatEndAsOpen, true)

  controller.endDateValue = "c"
  assert.equal(range.realtimeDateRange().treatEndAsOpen, false)

  controller.defaultDateRange = undefined
  controller.startDateValue = controller.endDateValue = undefined
  assert.equal(range.realtimeDateRange().treatEndAsOpen, false)
})
