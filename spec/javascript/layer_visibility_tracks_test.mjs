import assert from "node:assert/strict"
import test from "node:test"
import { LayerVisibilityManager } from "controllers/maps/maplibre/layer_visibility_manager"
import { Toast } from "maps_maplibre/components/toast"
import { lazyLoader } from "maps_maplibre/utils/lazy_loader"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

test("track visibility controls tile lines and focused selection together", async (t) => {
  t.mock.method(SettingsManager, "updateSetting", () => {})
  const actions = []
  const layers = {
    "tracks-mvt": { setEnabled: (enabled) => actions.push(["tile", enabled]) },
    tracks: { toggle: (enabled) => actions.push(["selection", enabled]) },
  }
  const controller = {
    map: {},
    settings: {},
    layerManager: { getLayer: (name) => layers[name] },
    eventHandlers: {
      selectedTrackFeature: { properties: { id: 7 } },
      clearTrackSelection: () => actions.push(["clear"]),
    },
  }
  const manager = new LayerVisibilityManager(controller)

  await manager.toggleTracks({ target: { checked: false } })
  assert.deepEqual(actions, [["tile", false], ["selection", false], ["clear"]])

  actions.length = 0
  await manager.toggleTracks({ target: { checked: true } })
  assert.deepEqual(actions, [
    ["tile", true],
    ["selection", true],
  ])
})

test("a failed first Scratch membership fetch retries the registered layer instead of leaking another", async (t) => {
  let installed = false
  let instances = 0
  let listeners = 0
  let retryCalls = 0
  let retry = null
  t.mock.method(Toast, "retry", (_message, _label, callback) => {
    retry = callback
  })
  t.mock.method(SettingsManager, "updateSetting", () => {})
  t.mock.method(console, "error", () => {})
  class ScratchLayerDouble {
    constructor() {
      this.id = "scratch"
      instances += 1
    }
    async add() {
      installed = true
      listeners += 1
      throw new Error("membership offline")
    }
    show() {
      retryCalls += 1
    }
    remove() {
      installed = false
      listeners -= 1
    }
  }
  t.mock.method(lazyLoader, "loadLayer", async () => ScratchLayerDouble)
  const layers = {}
  const controller = {
    map: { getLayer: () => installed },
    settings: {},
    api: {},
    startDateValue: "2024-07-01",
    endDateValue: "2024-07-31",
    userPlanValue: "pro",
    layerManager: {
      layers,
      getLayer: (name) => (name === "scratch" ? layers.scratchLayer : null),
    },
  }
  const manager = new LayerVisibilityManager(controller)
  manager.reapplyPointsRenderer = async () => {}
  await manager.toggleScratch({ target: { checked: true } })
  assert.equal(instances, 1)
  assert.equal(listeners, 1)
  assert.ok(layers.scratchLayer)
  assert.equal(typeof retry, "function")

  await retry()
  assert.equal(instances, 1)
  assert.equal(listeners, 1)
  assert.equal(retryCalls, 1)
})

test("a Lite fog toggle runs as a gated preview without persisting fogEnabled", async (t) => {
  t.mock.method(Toast, "info", () => null)
  t.mock.method(Toast, "dismiss", () => {})
  const updateSetting = t.mock.method(
    SettingsManager,
    "updateSetting",
    () => {},
  )
  const shown = []
  const controller = {
    map: {},
    settings: {},
    userPlanValue: "lite",
    gatedLayersValue: ["Fog of War"],
    layerManager: {
      getLayer: () => ({ toggle: (enabled) => shown.push(enabled) }),
    },
  }
  const manager = new LayerVisibilityManager(controller)

  await manager.toggleFog({ target: { checked: true } })
  await new Promise((resolve) => setImmediate(resolve))
  await manager.toggleFog({ target: { checked: false } })

  assert.deepEqual(shown, [true, false])
  assert.equal(updateSetting.mock.callCount(), 0)
})
