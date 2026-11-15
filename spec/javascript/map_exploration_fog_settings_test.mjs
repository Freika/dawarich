import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const startupSource = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/maps/maplibre/map_startup.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const { loadViewSettings } = await import(
  `data:text/javascript;base64,${Buffer.from(startupSource).toString("base64")}`
)

function buildController({ explorationBounds }) {
  const storedSettings = { fogEnabled: false, tracksEnabled: true }
  const controller = {
    hasExplorationBoundsValue: explorationBounds,
    timezoneValue: "Europe/Berlin",
    settingsController: {
      settings: storedSettings,
      loadSettings: async () => storedSettings,
    },
  }
  return { controller, storedSettings }
}

test("a city card turns fog on for the view without touching stored settings", async () => {
  const { controller, storedSettings } = buildController({
    explorationBounds: true,
  })

  await loadViewSettings(controller)

  assert.equal(controller.settings.fogEnabled, true)
  assert.equal(storedSettings.fogEnabled, false)
})

test("without a city card the map uses the stored settings as they are", async () => {
  const { controller, storedSettings } = buildController({
    explorationBounds: false,
  })

  await loadViewSettings(controller)

  assert.equal(controller.settings, storedSettings)
  assert.equal(controller.settings.timezone, "Europe/Berlin")
})
