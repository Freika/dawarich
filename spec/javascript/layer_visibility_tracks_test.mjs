import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/layer_visibility_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const dependencies = `
const SettingsManager = { updateSetting() {} }
const translate = (key) => key
const Toast = { retry(_message, _label, callback) { globalThis.__scratchRetry = callback } }
const gatedToggle = () => false
const lazyLoader = { loadLayer: async () => globalThis.__scratchTestLayer }
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(dependencies + withoutImports).toString("base64")}`
const { LayerVisibilityManager } = await import(moduleUrl)

test("track visibility controls tile lines and focused selection together", async () => {
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

test("a failed first Scratch membership fetch retries the registered layer instead of leaking another", async () => {
  let installed = false
  let instances = 0
  let listeners = 0
  let retryCalls = 0
  globalThis.__scratchRetry = null
  globalThis.__scratchTestLayer = class {
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
  const originalError = console.error
  console.error = () => {}
  try {
    await manager.toggleScratch({ target: { checked: true } })
    assert.equal(instances, 1)
    assert.equal(listeners, 1)
    assert.ok(layers.scratchLayer)
    assert.equal(typeof globalThis.__scratchRetry, "function")

    await globalThis.__scratchRetry()
    assert.equal(instances, 1)
    assert.equal(listeners, 1)
    assert.equal(retryCalls, 1)
  } finally {
    console.error = originalError
    delete globalThis.__scratchTestLayer
    delete globalThis.__scratchRetry
  }
})
