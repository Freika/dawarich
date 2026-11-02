import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre_realtime_controller.js",
    import.meta.url,
  ),
  "utf8",
)
globalThis.SettingsManagerStub = {}
globalThis.RangeStub = () => true
const SettingsManagerStub = globalThis.SettingsManagerStub
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
    'import { pointMatchesActiveDateRange } from "maps_maplibre/utils/realtime_date_filter"',
    "const pointMatchesActiveDateRange = (...args) => globalThis.RangeStub(...args)",
  )
  .replace(
    'import { SettingsManager } from "maps_maplibre/utils/settings_manager"',
    "const SettingsManager = globalThis.SettingsManagerStub",
  )
const { default: RealtimeController } = await import(
  `data:text/javascript;base64,${Buffer.from(stubbedSource).toString("base64")}`
)

function buildController() {
  const calls = {
    pointsRefresh: 0,
    filters: 0,
    scratchUpdate: 0,
    recentPoints: [],
  }
  const layers = {
    "points-mvt": { refresh: () => calls.pointsRefresh++ },
    "map-editor": { reapplyTileFilters: () => calls.filters++ },
    scratch: {
      update: () => {
        calls.scratchUpdate++
        return Promise.resolve()
      },
    },
    recentPoint: {
      show() {},
      updateRecentPoint: (lon, lat) => calls.recentPoints.push([lon, lat]),
    },
  }
  const mapsController = {
    layerManager: { getLayer: (id) => layers[id] },
    realtimeDateRange: () => ({}),
    map: { flyTo() {}, getZoom: () => 10 },
  }
  const controller = new RealtimeController()
  controller.element = {}
  controller.application = {
    getControllerForElementAndIdentifier: () => mapsController,
  }
  return { controller, calls, mapsController }
}

function livePoint(index) {
  return [52.5, 13.4, 80, 30, 1758196800 + index, 1.2, index + 1, "Germany"]
}

function installFakeTimers(t) {
  const pending = new Map()
  const delays = []
  let nextId = 1
  const originalSetTimeout = globalThis.setTimeout
  const originalClearTimeout = globalThis.clearTimeout
  globalThis.setTimeout = (callback, delay) => {
    delays.push(delay)
    const id = nextId++
    pending.set(id, callback)
    return id
  }
  globalThis.clearTimeout = (id) => {
    pending.delete(id)
  }
  t.after(() => {
    globalThis.setTimeout = originalSetTimeout
    globalThis.clearTimeout = originalClearTimeout
  })
  return {
    delays,
    runPending() {
      for (const [id, callback] of [...pending]) {
        pending.delete(id)
        callback()
      }
    },
  }
}

test("a burst of live points triggers a single tile and visited-countries refresh", (t) => {
  const timers = installFakeTimers(t)
  const { controller, calls } = buildController()

  for (let index = 0; index < 100; index++) {
    controller.handleNewPoint(livePoint(index))
  }

  assert.equal(calls.pointsRefresh, 0)
  assert.equal(calls.scratchUpdate, 0)
  assert.deepEqual(timers.delays, [1000])

  timers.runPending()

  assert.equal(calls.pointsRefresh, 1)
  assert.equal(calls.filters, 1)
  assert.equal(calls.scratchUpdate, 1)
})

test("a live point after a completed refresh schedules another one", (t) => {
  const timers = installFakeTimers(t)
  const { controller, calls } = buildController()

  controller.handleNewPoint(livePoint(0))
  timers.runPending()
  controller.handleNewPoint(livePoint(1))
  timers.runPending()

  assert.equal(calls.pointsRefresh, 2)
})

test("disconnect cancels a pending live refresh", (t) => {
  const timers = installFakeTimers(t)
  const { controller, calls } = buildController()

  controller.handleNewPoint(livePoint(0))
  controller.disconnect()
  timers.runPending()

  assert.equal(calls.pointsRefresh, 0)
  assert.equal(calls.scratchUpdate, 0)
})

test("turning live mode off keeps the current position marker", () => {
  const { controller } = buildController()
  const recentPoint =
    controller.mapsV2Controller.layerManager.getLayer("recentPoint")
  let hidden = false
  let cleared = false
  recentPoint.hide = () => {
    hidden = true
  }
  recentPoint.clear = () => {
    cleared = true
  }
  controller.channels = { unsubscribeAll() {} }
  controller.setupChannels = () => {}
  SettingsManagerStub.updateSetting = () => {}

  controller.toggleLiveMode({ target: { checked: false } })

  assert.equal(hidden, false)
  assert.equal(cleared, false)
})

test("a live point outside the viewed date range still moves the current position", (t) => {
  const timers = installFakeTimers(t)
  globalThis.RangeStub = () => false
  t.after(() => {
    globalThis.RangeStub = () => true
  })
  const { controller, calls } = buildController()

  controller.handleNewPoint(livePoint(0))

  assert.deepEqual(calls.recentPoints, [[13.4, 52.5]])
  assert.deepEqual(timers.delays, [])
})

test("a live point becomes the position restored after a map style change", (t) => {
  installFakeTimers(t)
  const { controller, mapsController } = buildController()

  controller.handleNewPoint(livePoint(3))

  assert.deepEqual(mapsController.currentPositionValue, {
    longitude: 13.4,
    latitude: 52.5,
    timestamp: 1758196803,
  })
})

test("a live point older than the current position leaves the dot in place", (t) => {
  installFakeTimers(t)
  const { controller, calls, mapsController } = buildController()
  mapsController.currentPositionValue = {
    longitude: 1,
    latitude: 2,
    timestamp: 1758196900,
  }

  controller.handleNewPoint(livePoint(0))

  assert.deepEqual(calls.recentPoints, [])
  assert.equal(mapsController.currentPositionValue.timestamp, 1758196900)
})

test("a background track event updates displayed distance with live points disabled", async (t) => {
  const timers = installFakeTimers(t)
  const statisticsSource = (
    await readFile(
      new URL(
        "../../app/javascript/maps_maplibre/components/range_statistics.js",
        import.meta.url,
      ),
      "utf8",
    )
  ).replace(/^import .*\n/gm, "")
  const prelude = `const formatNumber = String; const translate = (key, values) => values ? JSON.stringify(values) : key;\n`
  const { RangeStatistics } = await import(
    `data:text/javascript;base64,${Buffer.from(prelude + statisticsSource).toString("base64")}`
  )
  const { controller, mapsController } = buildController()
  controller.liveModeEnabled = false
  const element = { textContent: "", setAttribute() {} }
  let distance = 1000
  const requests = []
  mapsController.rangeStatistics = new RangeStatistics(element, {
    fetchRangeStatistics: async ({ start_at, end_at }) => {
      requests.push([start_at, end_at])
      return { points: 2, distance_meters: distance }
    },
  })
  await mapsController.rangeStatistics.load("selected-start", "selected-end")
  assert.equal(JSON.parse(element.textContent).distance, "1")
  distance = 0
  controller.handleReceived({ type: "track_update" })
  timers.runPending()
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(JSON.parse(element.textContent).distance, "0")
  assert.deepEqual(requests, [
    ["selected-start", "selected-end"],
    ["selected-start", "selected-end"],
  ])
})
