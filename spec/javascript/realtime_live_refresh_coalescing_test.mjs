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
    "const pointMatchesActiveDateRange = () => true",
  )
  .replace(
    'import { SettingsManager } from "maps_maplibre/utils/settings_manager"',
    "const SettingsManager = {}",
  )
const { default: RealtimeController } = await import(
  `data:text/javascript;base64,${Buffer.from(stubbedSource).toString("base64")}`
)

function buildController() {
  const calls = { pointsRefresh: 0, filters: 0, scratchUpdate: 0 }
  const layers = {
    "points-mvt": { refresh: () => calls.pointsRefresh++ },
    "map-editor": { reapplyTileFilters: () => calls.filters++ },
    scratch: {
      update: () => {
        calls.scratchUpdate++
        return Promise.resolve()
      },
    },
    recentPoint: { show() {}, updateRecentPoint() {} },
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
  return { controller, calls }
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
