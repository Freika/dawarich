import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/settings_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const stubs = `
const translate = (key) => key
const Toast = { success() {}, error() {} }
const UpgradeBanner = class {}
const isGatedPlan = () => false
const getMapStyle = () => null
const BACKEND_SETTINGS_MAP = {}
const LAYER_NAME_MAP = {}
const basemapUrlFor = () => null
const SettingsManager = globalThis.__settingsManagerStub
`
globalThis.CustomEvent ??= class CustomEvent extends Event {}
globalThis.document = new EventTarget()
globalThis.FormData = class {
  get() {
    return "5"
  }
}
globalThis.__settingsManagerStub = { updateSettings: async () => null }

const moduleUrl = `data:text/javascript;base64,${Buffer.from(stubs + withoutImports).toString("base64")}`
const { SettingsController } = await import(moduleUrl)

test("saving advanced settings keeps the settings object other code holds", async () => {
  const shared = { minutesBetweenRoutes: 60 }
  const controller = { settings: shared }
  const settingsController = new SettingsController(controller)

  await settingsController.updateAdvancedSettings({
    preventDefault() {},
    target: {},
  })

  assert.equal(controller.settings, shared)
  assert.equal(shared.minutesBetweenRoutes, 5)
})
