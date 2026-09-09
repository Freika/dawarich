import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function loadFamilyMapController(theme = "dark") {
  const source = await readFile(
    new URL(
      "../../app/javascript/controllers/family_map_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
  const withoutImports = source.replace(/^import .*\n/gm, "")
  const dependencies = `
    class Controller {}
    class LngLatBounds {
      constructor() { this.coordinates = [] }
      extend(coordinates) { this.coordinates.push(coordinates) }
    }
    const maplibregl = { LngLatBounds }
    const escapeHtml = (value) => value
    const getCurrentTheme = () => ${JSON.stringify(theme)}
    const getMapStyle = async () => ({})
  `
  const url = `data:text/javascript;base64,${Buffer.from(`${dependencies}\n${withoutImports}`).toString("base64")}`

  return (await import(`${url}#${Date.now()}`)).default
}

test("family member labels render before the map fits their bounds", async () => {
  const FamilyMapController = await loadFamilyMapController()
  const controller = new FamilyMapController()
  const layers = []
  const fitCalls = []
  controller.locationsValue = [
    {
      user_id: 1,
      email: "member@example.test",
      longitude: 13.405,
      latitude: 52.52,
      timestamp: 1_700_000_000,
    },
  ]
  controller.map = {
    addSource() {},
    addLayer(layer) {
      layers.push(layer)
    },
    on() {},
    fitBounds(bounds, options) {
      fitCalls.push({ bounds, options })
    },
  }

  controller.addMembers()

  const labels = layers.find((layer) => layer.id === "family-labels")
  assert.equal(labels.paint["text-color"], "#e5e7eb")
  assert.deepEqual(fitCalls[0].bounds.coordinates, [[13.405, 52.52]])
  assert.deepEqual(fitCalls[0].options, { padding: 60, maxZoom: 14 })
})
