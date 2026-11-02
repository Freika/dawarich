import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre_controller.js",
    import.meta.url,
  ),
  "utf8",
)

const start = source.indexOf("  async loadViewSettings() {")
const end = source.indexOf("\n  }\n", start) + 4
const methodSource = source.slice(start, end)

async function buildController({ explorationBounds }) {
  const { default: Controller } = await import(
    `data:text/javascript;base64,${Buffer.from(`export default class { ${methodSource} }`).toString("base64")}#${Math.random()}`
  )
  const storedSettings = { fogEnabled: false, tracksEnabled: true }
  const controller = new Controller()
  controller.hasExplorationBoundsValue = explorationBounds
  controller.timezoneValue = "Europe/Berlin"
  controller.settingsController = {
    settings: storedSettings,
    loadSettings: async () => storedSettings,
  }
  return { controller, storedSettings }
}

test("a city card turns fog on for the view without touching stored settings", async () => {
  assert.ok(start > 0, "loadViewSettings exists")
  const { controller, storedSettings } = await buildController({
    explorationBounds: true,
  })

  await controller.loadViewSettings()

  assert.equal(controller.settings.fogEnabled, true)
  assert.equal(storedSettings.fogEnabled, false)
})

test("without a city card the map uses the stored settings as they are", async () => {
  const { controller, storedSettings } = await buildController({
    explorationBounds: false,
  })

  await controller.loadViewSettings()

  assert.equal(controller.settings, storedSettings)
  assert.equal(controller.settings.timezone, "Europe/Berlin")
})
