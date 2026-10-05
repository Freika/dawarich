import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const helperDateSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/realtime_date_filter.js",
    import.meta.url,
  ),
  "utf8",
)
const helperDateUrl = `data:text/javascript;base64,${Buffer.from(helperDateSource).toString("base64")}`
const helperSource = (
  await readFile(
    new URL(
      "../../app/javascript/maps_maplibre/utils/realtime_points.js",
      import.meta.url,
    ),
    "utf8",
  )
)
  .replace('import { translate } from "i18n"', "const translate = (key) => key")
  .replace(
    'import { Toast } from "maps_maplibre/components/toast"',
    "const Toast = { info() {}, retry() {} }",
  )
  .replace(
    '"maps_maplibre/utils/realtime_date_filter"',
    JSON.stringify(helperDateUrl),
  )
const helperUrl = `data:text/javascript;base64,${Buffer.from(helperSource).toString("base64")}`

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre_realtime_controller.js",
    import.meta.url,
  ),
  "utf8",
)
const stubbedSource = source
  .replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}",
  )
  .replace('import { translate } from "i18n"', "const translate = (key) => key")
  .replace(
    'import { createMapChannel } from "maps_maplibre/channels/map_channel"',
    "const createMapChannel = () => ({})",
  )
  .replace(
    'import { Toast } from "maps_maplibre/components/toast"',
    "const Toast = { info() {}, retry() {} }",
  )
  .replace(
    'import { SettingsManager } from "maps_maplibre/utils/settings_manager"',
    "const SettingsManager = {}",
  )
  .replace(
    /import \{\s*handleNewPoint,[\s\S]*?\} from "maps_maplibre\/utils\/realtime_points"/,
    `import { handleNewPoint, refreshLiveLayers, updateRecentPoint, zoomToPoint } from "${helperUrl}"`,
  )
const { default: RealtimeController } = await import(
  `data:text/javascript;base64,${Buffer.from(stubbedSource).toString("base64")}`
)

const railsPoint = {
  source: "app/models/point.rb#broadcast_coordinates",
  spec: "spec/models/point_spec.rb",
  example: "broadcasts the complete live point tuple with a nonempty country",
  tuple: [52.52, 13.405, "85", "100.0", "1700000000", "5", "405", "Germany"],
}

function buildController(t) {
  const calls = { markers: [], flights: [], invalidations: [], shows: 0 }
  const pending = new Map()
  const originalSetTimeout = globalThis.setTimeout
  const originalClearTimeout = globalThis.clearTimeout
  let nextId = 1
  globalThis.setTimeout = (callback) => {
    const id = nextId++
    pending.set(id, callback)
    return id
  }
  globalThis.clearTimeout = (id) => pending.delete(id)
  t.after(() => {
    globalThis.setTimeout = originalSetTimeout
    globalThis.clearTimeout = originalClearTimeout
  })
  const recentPoint = {
    show: () => calls.shows++,
    updateRecentPoint: (...args) => calls.markers.push(args),
  }
  const maps = {
    realtimeDateRange: () => ({
      startValue: "2023-11-14T00:00:00Z",
      endValue: "2023-11-14T23:59:59Z",
    }),
    layerManager: {
      getLayer: (id) => (id === "recentPoint" ? recentPoint : null),
    },
    mapDataManager: {
      invalidatePoints: (options) => calls.invalidations.push(options),
    },
    map: { getZoom: () => 10, flyTo: (options) => calls.flights.push(options) },
  }
  const controller = new RealtimeController()
  controller.liveModeEnabled = true
  controller.element = {}
  controller.application = { getControllerForElementAndIdentifier: () => maps }
  return { controller, calls, pending }
}

test("live point delivery preserves tuple fields and longitude latitude marker order", (t) => {
  const { controller, calls, pending } = buildController(t)
  controller.handleNewPoint(railsPoint.tuple)

  assert.deepEqual(calls.markers, [
    [
      13.405,
      52.52,
      {
        id: 405,
        battery: 85,
        altitude: 100,
        timestamp: "1700000000",
        velocity: 5,
        country_name: "Germany",
      },
    ],
  ])
  assert.deepEqual(calls.flights, [
    { center: [13.405, 52.52], zoom: 14, duration: 2000, essential: true },
  ])
  assert.deepEqual(calls.invalidations, [{ appendOnly: true }])
  assert.equal(calls.shows, 1)
  assert.equal(pending.size, 1)
})

test("a point outside the active date window causes no map mutation", (t) => {
  const { controller, calls, pending } = buildController(t)
  const tuple = [...railsPoint.tuple]
  tuple[4] = "1699913600"
  controller.handleNewPoint(tuple)

  assert.deepEqual(calls, {
    markers: [],
    flights: [],
    invalidations: [],
    shows: 0,
  })
  assert.equal(pending.size, 0)
})
