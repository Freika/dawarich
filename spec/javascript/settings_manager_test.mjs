import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// CI runs Node 18, which has no global CustomEvent.
globalThis.CustomEvent ??= class CustomEvent extends Event {
  constructor(type, options = {}) {
    super(type, options)
    this.detail = options.detail ?? null
  }
}

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
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+";?\n/gm, "")
const combinedSource = `${basemapUrlSource}\n${withoutImports}`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(combinedSource).toString("base64")}`
const { BACKEND_SETTINGS_MAP, LAYER_NAME_MAP, SettingsManager } = await import(
  moduleUrl
)
const freshAccountSettings = JSON.parse(
  await readFile(
    new URL("../fixtures/user_settings_defaults.json", import.meta.url),
    "utf8",
  ),
)

function stubFetch(handler) {
  const originalFetch = globalThis.fetch
  const calls = []
  globalThis.fetch = async (url, options = {}) => {
    calls.push({ url, method: options.method ?? "GET", options })
    return handler(url, options)
  }
  return {
    calls,
    restore: () => {
      globalThis.fetch = originalFetch
    },
  }
}

const jsonResponse = (body, ok = true) => ({
  ok,
  status: ok ? 200 : 500,
  json: async () => body,
})

test("the server returns every setting the map reads, so the map keeps no defaults", () => {
  const missing = Object.values(BACKEND_SETTINGS_MAP).filter(
    (backendKey) => !(backendKey in freshAccountSettings),
  )
  assert.deepEqual(missing, [])
})

test("before settings load there are no client-side defaults", () => {
  SettingsManager.initialize("test-key")
  const settings = SettingsManager.getSettings()
  assert.equal(settings.fogOfWarMode, undefined)
  assert.equal(settings.mapStyle, undefined)
})

test("a fresh account loads the server defaults", async () => {
  const fetchStub = stubFetch(() =>
    jsonResponse({ settings: freshAccountSettings }),
  )
  try {
    SettingsManager.initialize("test-key")
    const loaded = await SettingsManager.loadFromBackend()
    assert.equal(loaded.fogOfWarMode, "hexagons")
    assert.equal(loaded.globeProjection, true)
    assert.equal(loaded.fogOfWarRadius, 50)
    assert.equal(loaded.speedColorScale, freshAccountSettings.speed_color_scale)
  } finally {
    fetchStub.restore()
  }
})

test("nothing is saved after settings failed to load", async () => {
  const fetchStub = stubFetch(() => jsonResponse({}, false))
  try {
    SettingsManager.initialize("test-key")
    await SettingsManager.sync()
    assert.equal(SettingsManager.loaded, false)
    await SettingsManager.updateSetting("globeProjection", false)
    assert.deepEqual(
      fetchStub.calls.filter((call) => call.method === "PATCH"),
      [],
    )
  } finally {
    fetchStub.restore()
  }
})

test("reset asks the server to delete appearance settings and uses its answer", async () => {
  const fetchStub = stubFetch((_url, options) =>
    options.method === "DELETE"
      ? jsonResponse({ settings: freshAccountSettings })
      : jsonResponse({
          settings: { ...freshAccountSettings, maps_maplibre_style: "dark" },
        }),
  )
  try {
    SettingsManager.initialize("test-key")
    await SettingsManager.loadFromBackend()
    const settings = await SettingsManager.resetToDefaults()
    const reset = fetchStub.calls.find((call) => call.method === "DELETE")
    assert.equal(reset.url, "/api/v1/settings/appearance")
    assert.equal(settings.mapStyle, "light")
    assert.equal(SettingsManager.getSettings().mapStyle, "light")
  } finally {
    fetchStub.restore()
  }
})

test("reset can be limited to some appearance settings", async () => {
  const fetchStub = stubFetch(() =>
    jsonResponse({ settings: freshAccountSettings }),
  )
  try {
    SettingsManager.initialize("test-key")
    await SettingsManager.resetToDefaults(["track_color"])
    const reset = fetchStub.calls.find((call) => call.method === "DELETE")
    assert.equal(reset.url, "/api/v1/settings/appearance?keys[]=track_color")
  } finally {
    fetchStub.restore()
  }
})

test("a settings object loaded earlier sees a reset", async () => {
  const loaded = { trackColor: "#111111", photosEnabled: true }
  SettingsManager.cachedSettings = loaded
  const fetchStub = stubFetch(() => ({
    ok: true,
    status: 200,
    json: async () => ({ settings: { track_color: "#6366F1" } }),
  }))

  try {
    SettingsManager.apiKey = "key"
    await SettingsManager.resetToDefaults(["track_color"])
    assert.equal(loaded.trackColor, "#6366F1")
  } finally {
    fetchStub.restore()
  }
})

test("a failed reset reports no settings", async () => {
  const fetchStub = stubFetch(() => jsonResponse({}, false))
  try {
    SettingsManager.initialize("test-key")
    assert.equal(await SettingsManager.resetToDefaults(), null)
  } finally {
    fetchStub.restore()
  }
})

async function patchBodyAfter(change) {
  const fetchStub = stubFetch(() =>
    jsonResponse({ settings: freshAccountSettings }),
  )
  try {
    SettingsManager.initialize("test-key")
    await SettingsManager.loadFromBackend()
    await change()
    const patch = fetchStub.calls.find((call) => call.method === "PATCH")
    return JSON.parse(patch.options.body).settings
  } finally {
    fetchStub.restore()
  }
}

test("a single change sends only that setting", async () => {
  const body = await patchBodyAfter(() =>
    SettingsManager.updateSetting("globeProjection", false),
  )
  assert.deepEqual(body, { globe_projection: false })
})

test("a layer toggle sends only the layer list", async () => {
  const body = await patchBodyAfter(() =>
    SettingsManager.updateSetting("heatmapEnabled", false),
  )
  assert.deepEqual(Object.keys(body), ["enabled_map_layers"])
  assert.equal(body.enabled_map_layers.includes("Heatmap"), false)
  assert.equal(body.enabled_map_layers.includes("Tracks"), true)
})

test("a nested map setting sends only that nested key", async () => {
  const body = await patchBodyAfter(() =>
    SettingsManager.updateSetting("hiddenTileCategories", ["roads"]),
  )
  assert.deepEqual(body, { maps: { hidden_tile_categories: ["roads"] } })
})

test("speed coloring preferences load and persist with the existing backend keys", async () => {
  const originalFetch = globalThis.fetch
  let saved
  globalThis.fetch = async (_url, options = {}) => {
    if (options.method === "PATCH") {
      saved = JSON.parse(options.body).settings
      return { ok: true, json: async () => ({ settings: saved }) }
    }
    return {
      ok: true,
      json: async () => ({
        settings: {
          speed_colored_routes: "true",
          speed_color_scale: "0:#000000|80:#ffffff",
        },
      }),
    }
  }
  try {
    SettingsManager.initialize("test-key")
    const loaded = await SettingsManager.loadFromBackend()
    assert.equal(loaded.speedColoredRoutes, true)
    assert.equal(loaded.speedColorScale, "0:#000000|80:#ffffff")
    await SettingsManager.saveToBackend(loaded)
    assert.equal(saved.speed_colored_routes, true)
    assert.equal(saved.speed_color_scale, loaded.speedColorScale)
    await SettingsManager.updateSetting("speedColoredRoutes", false)
    assert.equal(saved.speed_colored_routes, false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

async function loadSettingsController(settingsManager, overrides = {}) {
  const controllerSource = await readFile(
    new URL(
      "../../app/javascript/controllers/maps/maplibre/settings_manager.js",
      import.meta.url,
    ),
    "utf8",
  )
  const stripImports = (code) =>
    code.replace(/^import[\s\S]*?from "[^"]+";?\n/gm, "")
  const formSyncSource = await readFile(
    new URL(
      "../../app/javascript/controllers/maps/maplibre/settings_form_sync.js",
      import.meta.url,
    ),
    "utf8",
  )
  const withoutImports = `${stripImports(formSyncSource).replace(/^export /gm, "")}\n${stripImports(controllerSource)}`
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
    const isGatedPlan = globalThis.__settingsManagerIsGatedPlan ?? (() => false)
    const LAYER_NAME_MAP = ${JSON.stringify(LAYER_NAME_MAP ?? {})}
    const SettingsManager = globalThis.__settingsManagerTestDouble
    const TransportationSettings = class { syncTransportationSettings() {} }
    const applyGlobeProjection = () => {}
    const globeEnabled = () => false
    const getMapStyle = globalThis.__settingsManagerGetMapStyle
    const translate = globalThis.__settingsManagerTranslate ?? ((key) => key)
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

test("Track generation thresholds load and persist with their existing backend keys", async () => {
  const originalFetch = globalThis.fetch
  let saved
  globalThis.fetch = async (_url, options = {}) => {
    if (options.method === "PATCH") {
      saved = JSON.parse(options.body).settings
      return { ok: true, json: async () => ({ settings: saved }) }
    }
    return {
      ok: true,
      json: async () => ({
        settings: {
          meters_between_routes: 1200,
          minutes_between_routes: 45,
          split_tracks_at_midnight: true,
        },
      }),
    }
  }

  try {
    SettingsManager.apiKey = "test-key"
    const loaded = await SettingsManager.loadFromBackend()
    assert.equal(loaded.metersBetweenRoutes, 1200)
    assert.equal(loaded.minutesBetweenRoutes, 45)
    assert.equal(loaded.splitTracksAtMidnight, true)
    await SettingsManager.saveToBackend(loaded)
    assert.equal(saved.meters_between_routes, "1200")
    assert.equal(saved.minutes_between_routes, "45")
    assert.equal(saved.split_tracks_at_midnight, true)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("a saved Areas layer carries over to Places with their boundaries", async () => {
  const originalFetch = globalThis.fetch
  globalThis.fetch = async () => ({
    ok: true,
    json: async () => ({
      settings: { enabled_map_layers: ["Tracks", "Areas"] },
    }),
  })

  try {
    SettingsManager.apiKey = "test-key"
    const loaded = await SettingsManager.loadFromBackend()
    assert.equal(loaded.placesEnabled, true)
    assert.equal(loaded.placeBoundariesEnabled, true)
    assert.equal(loaded.enabledMapLayers.includes("Areas"), false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("a loaded settings object sees later updates", async () => {
  const loaded = { photosEnabled: false, mapStyle: "light" }
  SettingsManager.cachedSettings = loaded
  SettingsManager.saveToBackend = async (settings) => settings

  await SettingsManager.updateSetting("photosEnabled", true)

  assert.equal(loaded.photosEnabled, true)
})

test("multiple setting updates are persisted in one write", async () => {
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

  await SettingsManager.updateSettings({
    trackColor: "#6366F1",
    mapStyle: "dark",
  })

  assert.equal(snapshots.length, 1)
  assert.deepEqual(snapshots[0], { trackColor: "#6366F1", mapStyle: "dark" })
})

test("settings writes are serialized so a newer change persists last", async () => {
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

  const staleSave = SettingsManager.updateSetting("trackColor", "#333333")
  await Promise.resolve()
  const resetSave = SettingsManager.updateSettings({ trackColor: "#6366F1" })
  await Promise.resolve()

  assert.equal(snapshots.length, 1)
  releaseFirstSave()
  await Promise.all([staleSave, resetSave])
  assert.deepEqual(snapshots, [
    { trackColor: "#333333" },
    { trackColor: "#6366F1" },
  ])
})

test("resetting layer colors asks the server and cancels stale debounced saves", async () => {
  const updates = []
  const applied = []
  const settingsManager = {
    updateSetting(key, value) {
      updates.push({ [key]: value })
    },
    async resetToDefaults(keys) {
      updates.push({ reset: keys })
      return { trackColor: "#6366F1" }
    },
  }
  const { SettingsController } = await loadSettingsController(settingsManager)
  const controller = new SettingsController({
    element: { querySelector: () => null },
    settings: {},
  })
  controller.applyTrackColor = (color) => applied.push(color)
  controller.layerColorTimers = {
    trackColor: setTimeout(
      () => settingsManager.updateSetting("trackColor", "#111111"),
      10,
    ),
  }

  await controller.resetLayerColors()
  await new Promise((resolve) => setTimeout(resolve, 25))

  assert.deepEqual(updates, [{ reset: ["track_color"] }])
  assert.deepEqual(applied, ["#6366F1"])
})

async function resetWith(resetResult) {
  const toasts = []
  const settingsManager = { resetToDefaults: async () => resetResult }
  const { SettingsController } = await loadSettingsController(settingsManager, {
    Toast: { error: (message) => toasts.push(message), success() {} },
  })
  const controller = new SettingsController({
    element: { querySelector: () => null },
  })
  const originalConfirm = globalThis.confirm
  const originalWindow = globalThis.window
  let reloaded = false
  globalThis.confirm = () => true
  globalThis.window = {
    location: {
      reload: () => {
        reloaded = true
      },
    },
  }
  try {
    await controller.resetSettings()
  } finally {
    globalThis.confirm = originalConfirm
    globalThis.window = originalWindow
  }
  return { reloaded, toasts }
}

test("Reset reloads the page once the server restored the defaults", async () => {
  const { reloaded, toasts } = await resetWith({ mapStyle: "light" })
  assert.equal(reloaded, true)
  assert.deepEqual(toasts, [])
})

test("a failed Reset keeps the page and shows an error", async () => {
  const { reloaded, toasts } = await resetWith(null)
  assert.equal(reloaded, false)
  assert.deepEqual(toasts, ["settings.reset_failed"])
})

test("a failed settings load shows an error", async () => {
  const toasts = []
  const settingsManager = { sync: async () => ({}), loaded: false }
  const { SettingsController } = await loadSettingsController(settingsManager, {
    Toast: { error: (message) => toasts.push(message), success() {} },
  })
  const controller = new SettingsController({ element: {} })

  await controller.loadSettings()

  assert.deepEqual(toasts, ["settings.load_failed"])
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

test("track color picker drives the tiled Tracks layer", async () => {
  const settingsManager = {
    getSettings: () => ({}),
    getSetting: () => false,
    updateSetting: () => {},
  }
  const { SettingsController } = await loadSettingsController(settingsManager)
  const colorCalls = []
  const controller = new SettingsController({
    element: { querySelector: () => null },
    map: { getLayer: () => null },
    layerManager: {
      getLayer: (name) =>
        name === "tracks-mvt"
          ? { setColors: (colors) => colorCalls.push(colors) }
          : null,
    },
  })

  controller.applyTrackColor("#abcdef")

  assert.deepEqual(colorCalls, [{ trackColor: "#abcdef" }])
})

test("style rebuild reloads enabled family labels after the new layers exist", async () => {
  const controller = await styleSwapController()
  const seen = []
  controller.controller.settings.familyEnabled = true
  controller.controller.loadMapData = async () => seen.push("layers")
  controller.controller.loadFamilyMembers = async () => seen.push("family")
  await controller.restoreStyleLayers()
  assert.deepEqual(seen, ["layers", "family"])

  seen.length = 0
  controller.controller._disconnected = true
  await controller.restoreStyleLayers()
  assert.deepEqual(seen, ["layers"])

  seen.length = 0
  controller.controller._disconnected = false
  controller.controller.settings.familyEnabled = false
  await controller.restoreStyleLayers()
  assert.deepEqual(seen, ["layers"])
})

test("live speed changes use current preferences and restore edit exclusions", async () => {
  const settings = {
    speedColoredRoutes: false,
    speedColorScale: "0:#000000|80:#ffffff",
  }
  const calls = []
  const { SettingsController } = await loadSettingsController({
    updateSetting(key, value) {
      settings[key] = value
    },
    getSetting(key) {
      return settings[key]
    },
  })
  const controller = new SettingsController({
    settings: {},
    layerManager: {
      getLayer(id) {
        return id === "tracks-mvt"
          ? {
              setSpeedColoring(value) {
                calls.push(value)
              },
            }
          : {
              reapplyTileFilters() {
                calls.push("exclusions")
              },
            }
      },
    },
  })
  controller.toggleSpeedColoredRoutes({ target: { checked: true } })
  assert.deepEqual(calls, [
    { enabled: true, scale: settings.speedColorScale },
    "exclusions",
  ])
  controller.updateSpeedColorScale({
    detail: { colorStops: "0:#ff0000|80:#00ff00" },
  })
  assert.deepEqual(calls.at(-2), {
    enabled: true,
    scale: "0:#ff0000|80:#00ff00",
  })
})

test("Lite toggles are forced off only for layers the server gates", async () => {
  globalThis.__settingsManagerIsGatedPlan = () => true
  const originalDocument = globalThis.document
  globalThis.document = { dispatchEvent() {} }
  try {
    const { SettingsController } = await loadSettingsController({
      getSetting: () => false,
    })
    const heatmapToggle = { checked: true }
    const fogToggle = { checked: false }
    const controller = new SettingsController({
      element: { querySelector: () => null },
      settings: {},
      userPlanValue: "lite",
      gatedLayersValue: ["Heatmap"],
      hasHeatmapToggleTarget: true,
      heatmapToggleTarget: heatmapToggle,
      hasFogToggleTarget: true,
      fogToggleTarget: fogToggle,
    })
    controller.settings = { heatmapEnabled: true, fogEnabled: true }

    controller.syncToggleStates()
    await new Promise((resolve) => setTimeout(resolve, 10))

    assert.equal(heatmapToggle.checked, false)
    assert.equal(fogToggle.checked, true)
  } finally {
    delete globalThis.__settingsManagerIsGatedPlan
    globalThis.document = originalDocument
  }
})

test("reset drops a pending colour save so it cannot land after the reset", async () => {
  const saved = []
  const { SettingsController } = await loadSettingsController({
    updateSetting: (key, value) => saved.push([key, value]),
    resetToDefaults: async () => true,
  })
  const controller = new SettingsController({
    element: { querySelector: () => null },
    layerManager: { getLayer: () => null },
  })
  const originalConfirm = globalThis.confirm
  const originalWindow = globalThis.window
  globalThis.confirm = () => true
  globalThis.window = { location: { reload() {} } }
  try {
    controller.updateTrackColor({ target: { value: "#abcdef" } })
    await controller.resetSettings()
    await new Promise((resolve) => setTimeout(resolve, 200))
    assert.deepEqual(saved, [])
  } finally {
    globalThis.confirm = originalConfirm
    globalThis.window = originalWindow
  }
})
