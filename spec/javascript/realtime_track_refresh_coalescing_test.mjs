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
  const calls = { tracksRefresh: 0, filters: 0 }
  const layers = {
    "tracks-mvt": { refresh: () => calls.tracksRefresh++ },
    "map-editor": { reapplyTileFilters: () => calls.filters++ },
  }
  const mapsController = {
    layerManager: { getLayer: (id) => layers[id] },
  }
  const controller = new RealtimeController()
  controller.element = {}
  controller.application = {
    getControllerForElementAndIdentifier: () => mapsController,
  }
  return { controller, calls }
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

test("a burst of track updates triggers a single tracks tile refresh", (t) => {
  const timers = installFakeTimers(t)
  const { controller, calls } = buildController()

  for (let index = 0; index < 120; index++) {
    controller.handleTrackUpdate({ type: "track_update", action: "created" })
  }

  assert.equal(calls.tracksRefresh, 0)
  assert.equal(timers.delays.length, 1)

  timers.runPending()

  assert.equal(calls.tracksRefresh, 1)
  assert.equal(calls.filters, 1)
})

test("a track update after a completed refresh schedules another one", (t) => {
  const timers = installFakeTimers(t)
  const { controller, calls } = buildController()

  controller.handleTrackUpdate({ type: "track_update" })
  timers.runPending()
  controller.handleTrackUpdate({ type: "track_update" })
  timers.runPending()

  assert.equal(calls.tracksRefresh, 2)
})

test("disconnect cancels a pending tracks refresh", (t) => {
  const timers = installFakeTimers(t)
  const { controller, calls } = buildController()

  controller.handleTrackUpdate({ type: "track_update" })
  controller.disconnect()
  timers.runPending()

  assert.equal(calls.tracksRefresh, 0)
})
