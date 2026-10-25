import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

let source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/map_data_manager.js",
    import.meta.url,
  ),
  "utf8",
)
source = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const dependencies = `
const translate = (key) => key
const Toast = { error() {} }
const UpgradeBanner = { show() { globalThis.bannersShown += 1 } }
const flightWindows = (geoJSON) => geoJSON?.windows || []
const isGatedPlan = () => true
const performanceMonitor = { mark() {}, measure() { return 0 } }
const trimOutlierCoords = (coords) => coords
const overlayAwarePadding = () => ({ top: 50, right: 50, bottom: 50, left: 50 })
const maplibregl = {}
`
const { MapDataManager } = await import(
  `data:text/javascript;base64,${Buffer.from(dependencies + source).toString("base64")}`
)

function bannersFor(startDate, dataWindowStart) {
  globalThis.bannersShown = 0
  const manager = new MapDataManager({
    startDateValue: startDate,
    dataWindowStartValue: dataWindowStart,
    upgradeUrlValue: "",
  })
  manager._showDataWindowBanner()
  return globalThis.bannersShown
}

test("follows the server's window start rather than a client-side 12 months", () => {
  const windowStart = new Date()
  const yesterday = new Date(windowStart.getTime() - 86_400_000)

  assert.equal(
    bannersFor(yesterday.toISOString(), windowStart.toISOString()),
    1,
  )
  assert.equal(bannersFor("2020-01-01T00:00:00Z", "2020-01-01T00:00:00Z"), 0)
})
