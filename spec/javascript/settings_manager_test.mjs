import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/settings_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { LAYER_COLOR_DEFAULTS, SettingsManager } = await import(moduleUrl)

async function loadSettingsController(settingsManager) {
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
  const dependencies = `
    const Toast = { error() {}, success() {} }
    const UpgradeBanner = {}
    const isGatedPlan = () => false
    const LAYER_COLOR_DEFAULTS = ${JSON.stringify(LAYER_COLOR_DEFAULTS)}
    const SettingsManager = globalThis.__settingsManagerTestDouble
    const getMapStyle = async () => ({})
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
