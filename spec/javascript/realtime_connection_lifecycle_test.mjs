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
    "export const settingsUpdates = []; const SettingsManager = { updateSetting: (...args) => settingsUpdates.push(args) }",
  )
  .replace(
    /import \{\s*handleNewPoint,[\s\S]*?\} from "maps_maplibre\/utils\/realtime_points"/,
    `import { handleNewPoint, refreshLiveLayers, updateRecentPoint, zoomToPoint } from "${helperUrl}"`,
  )
const { default: RealtimeController, settingsUpdates } = await import(
  `data:text/javascript;base64,${Buffer.from(stubbedSource).toString("base64")}`
)

function buildController() {
  const controller = new RealtimeController()
  const calls = []
  controller.enabledValue = true
  controller.liveModeValue = false
  controller.element = {}
  controller.application = { getControllerForElementAndIdentifier: () => null }
  controller.setupChannels = () => calls.push(controller.liveModeEnabled)
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
    pending,
    runPending() {
      for (const [id, callback] of [...pending]) {
        pending.delete(id)
        callback()
      }
    },
  }
}

test("disconnect before delayed setup never creates map subscriptions", (t) => {
  const timers = installFakeTimers(t)
  const { controller, calls } = buildController()
  controller.connect()
  controller.disconnect()
  timers.runPending()

  assert.deepEqual(calls, [])
  assert.equal(timers.pending.size, 0)
})

test("reconnect after early disconnect schedules exactly one setup", (t) => {
  const timers = installFakeTimers(t)
  const { controller, calls } = buildController()
  controller.connect()
  controller.disconnect()
  controller.liveModeValue = true
  controller.connect()
  assert.equal(timers.pending.size, 1)
  timers.runPending()

  assert.deepEqual(calls, [true])
  assert.equal(controller.setupTimer, null)
})

test("toggling live mode before delayed setup does not create a second subscription set", (t) => {
  const timers = installFakeTimers(t)
  const { controller, calls } = buildController()
  settingsUpdates.length = 0
  controller.connect()
  controller.toggleLiveMode({ target: { checked: true } })
  assert.deepEqual(calls, [true])
  timers.runPending()

  assert.deepEqual(calls, [true])
  assert.deepEqual(settingsUpdates, [["liveMapEnabled", true]])
  assert.equal(controller.setupTimer, null)
})
