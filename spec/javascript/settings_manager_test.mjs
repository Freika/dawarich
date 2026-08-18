import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const basemapUrlSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/basemap_url.js",
    import.meta.url,
  ),
  "utf8",
)
const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/settings_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const combinedSource = `${basemapUrlSource}\n${withoutImports}`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(combinedSource).toString("base64")}`
const { LAYER_COLOR_DEFAULTS, SettingsManager } = await import(moduleUrl)

async function loadSettingsController(settingsManager, overrides = {}) {
  const controllerSource = await readFile(
    new URL(
      "../../app/javascript/controllers/maps/maplibre/settings_manager.js",
      import.meta.url,
    ),
    "utf8",
  )
  const withoutImports = controllerSource.replace(
    /^import[\s\S]*?from "[^"]+"\n/gm,
    "",
  )
  globalThis.__settingsManagerTestDouble = settingsManager
  globalThis.__settingsManagerToast = overrides.Toast ?? {
    error() {},
    success() {},
  }
  globalThis.__settingsManagerGetMapStyle =
    overrides.getMapStyle ?? (async () => ({}))
  const dependencies = `
    const Toast = globalThis.__settingsManagerToast
    const UpgradeBanner = {}
    const isGatedPlan = () => false
    const LAYER_COLOR_DEFAULTS = ${JSON.stringify(LAYER_COLOR_DEFAULTS)}
    const SettingsManager = globalThis.__settingsManagerTestDouble
    const getMapStyle = globalThis.__settingsManagerGetMapStyle
    const translate = (key) => key
    ${basemapUrlSource.replace(/^export /gm, "")}
  `
  const url = `data:text/javascript;base64,${Buffer.from(`${dependencies}\n${withoutImports}`).toString("base64")}`
  return await import(`${url}#${Date.now()}`)
}

test("vector tile URLs require z, x, and y placeholders", () => {
  assert.equal(
    SettingsManager.validVectorTilesUrl(
      "https://tiles.example/{z}/{x}/{y}.mvt",
    ),
    true,
  )
  assert.equal(
    SettingsManager.validVectorTilesUrl("https://tiles.example/{z}.mvt"),
    false,
  )
  assert.equal(
    SettingsManager.validVectorTilesUrl("https://tiles.example/{z}/{x}.mvt"),
    false,
  )
  assert.equal(SettingsManager.validVectorTilesUrl(""), true)
})

test("basemap URLs also accept raster XYZ, style.json and suffixless style URLs", () => {
  assert.equal(
    SettingsManager.validVectorTilesUrl("https://t.example/{z}/{x}/{y}.png"),
    true,
  )
  assert.equal(
    SettingsManager.validVectorTilesUrl("https://t.example/style.json?key=a"),
    true,
  )
  assert.equal(
    SettingsManager.validVectorTilesUrl("https://t.example/basemap"),
    true,
  )
  assert.equal(
    SettingsManager.validVectorTilesUrl("//t.example/style.json"),
    false,
  )
})

test("multiple setting updates are persisted in one complete snapshot", async () => {
  SettingsManager.cachedSettings = {
    mapStyle: "light",
    routeColor: "#111111",
    trackColor: "#222222",
  }
  const snapshots = []
  SettingsManager.saveToBackend = async (settings) => {
    snapshots.push({ ...settings })
    return settings
  }

  await SettingsManager.updateSettings(LAYER_COLOR_DEFAULTS)

  assert.equal(snapshots.length, 1)
  assert.deepEqual(snapshots[0], {
    mapStyle: "light",
    routeColor: "#0000ff",
    trackColor: "#6366F1",
  })
})

test("settings writes are serialized so a newer snapshot persists last", async () => {
  SettingsManager.cachedSettings = {
    mapStyle: "light",
    routeColor: "#111111",
    trackColor: "#222222",
  }
  SettingsManager.saveQueue = Promise.resolve()
  let releaseFirstSave
  const firstSaveBlocked = new Promise((resolve) => {
    releaseFirstSave = resolve
  })
  const snapshots = []
  SettingsManager.saveToBackend = async (settings) => {
    snapshots.push({ ...settings })
    if (snapshots.length === 1) await firstSaveBlocked
    return settings
  }

  const staleSave = SettingsManager.updateSetting("routeColor", "#333333")
  await Promise.resolve()
  const resetSave = SettingsManager.updateSettings(LAYER_COLOR_DEFAULTS)
  await Promise.resolve()

  assert.equal(snapshots.length, 1)
  releaseFirstSave()
  await Promise.all([staleSave, resetSave])
  assert.deepEqual(snapshots.at(-1), {
    mapStyle: "light",
    routeColor: "#0000ff",
    trackColor: "#6366F1",
  })
})

test("resetting layer colors cancels stale debounced saves", async () => {
  const updates = []
  const settingsManager = {
    updateSetting(key, value) {
      updates.push({ [key]: value })
    },
    updateSettings(values) {
      updates.push(values)
    },
  }
  const { SettingsController } = await loadSettingsController(settingsManager)
  const controller = new SettingsController({
    element: { querySelector: () => null },
  })
  controller.applyRouteColor = () => {}
  controller.applyTrackColor = () => {}
  controller.layerColorTimers = {
    routeColor: setTimeout(
      () => settingsManager.updateSetting("routeColor", "#111111"),
      10,
    ),
  }

  controller.resetLayerColors()
  await new Promise((resolve) => setTimeout(resolve, 25))

  assert.deepEqual(updates, [LAYER_COLOR_DEFAULTS])
})

// Minimal stand-in for maplibregl.Map's Evented interface.
class FakeMap {
  constructor() {
    this.listeners = { "style.load": [], error: [] }
    this.setStyleCalls = []
  }

  on(event, callback) {
    this.listeners[event].push(callback)
  }

  once(event, callback) {
    const wrapped = (payload) => {
      this.off(event, wrapped)
      callback(payload)
    }
    this.on(event, wrapped)
  }

  off(event, callback) {
    this.listeners[event] = this.listeners[event].filter((c) => c !== callback)
  }

  emit(event, payload) {
    for (const callback of [...this.listeners[event]]) callback(payload)
  }

  setStyle(style, options) {
    this.setStyleCalls.push({ style, options })
  }
}

async function styleSwapController({ getMapStyle } = {}) {
  const { SettingsController } = await loadSettingsController(
    { getSetting: () => null },
    { getMapStyle, Toast: { error: (m) => toasts.push(m), success() {} } },
  )
  const controller = new SettingsController({
    element: { querySelector: () => null, querySelectorAll: () => [] },
    map: new FakeMap(),
    layerManager: { clearLayerReferences() {} },
    settings: {},
    loadMapData: () => restored.push("loadMapData"),
  })
  controller.restoreGlobeProjection = () => {}
  return controller
}

let toasts = []
let restored = []

test("a custom style URL is applied with diff disabled so style.load fires", async () => {
  toasts = []
  restored = []
  const controller = await styleSwapController()

  controller.applyUserStyleUrl("https://tiles.example/style.json", "light")

  assert.deepEqual(controller.map.setStyleCalls, [
    { style: "https://tiles.example/style.json", options: { diff: false } },
  ])

  controller.map.emit("style.load")
  assert.deepEqual(restored, ["loadMapData"])
  assert.deepEqual(toasts, [])
})

test("a failed tile request does not discard a working custom style", async () => {
  toasts = []
  restored = []
  const controller = await styleSwapController()

  controller.applyUserStyleUrl("https://tiles.example/style.json", "light")
  controller.map.emit("error", {
    error: { url: "https://tiles.example/tiles/3/4/5.pbf" },
  })

  assert.deepEqual(toasts, [])
  assert.equal(controller.map.setStyleCalls.length, 1)

  controller.map.emit("style.load")
  assert.deepEqual(restored, ["loadMapData"])
})

test("a failed style document reverts to the default style and reloads layers", async () => {
  toasts = []
  restored = []
  const fallback = { version: 8, sources: {}, layers: [] }
  const controller = await styleSwapController({
    getMapStyle: async () => fallback,
  })

  controller.applyUserStyleUrl("https://tiles.example/style.json", "light")
  controller.map.emit("error", {
    error: { url: "https://tiles.example/style.json" },
  })
  await new Promise((resolve) => setTimeout(resolve, 0))

  assert.equal(toasts.length, 1)
  assert.deepEqual(controller.map.setStyleCalls.at(-1), {
    style: fallback,
    options: { diff: false },
  })

  controller.map.emit("style.load")
  assert.deepEqual(restored, ["loadMapData"])
})

test("a stale style.load after the fallback does not double-reload", async () => {
  toasts = []
  restored = []
  const controller = await styleSwapController({
    getMapStyle: async () => ({ version: 8, sources: {}, layers: [] }),
  })

  controller.applyUserStyleUrl("https://tiles.example/style.json", "light")
  controller.map.emit("error", {
    error: { url: "https://tiles.example/style.json" },
  })
  await new Promise((resolve) => setTimeout(resolve, 0))

  controller.map.emit("style.load")
  controller.map.emit("style.load")

  assert.deepEqual(restored, ["loadMapData"])
})
