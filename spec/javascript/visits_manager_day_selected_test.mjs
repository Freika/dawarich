import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/visits_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const dependencies = `
  const translate = (key) => key
  class Toast {}
  class SettingsManager { static updateSetting() {} }
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(
  `${dependencies}\n${withoutImports}`,
).toString("base64")}`

globalThis.document = new EventTarget()
const { VisitsManager } = await import(moduleUrl)

// Selecting a day in Timeline outside the loaded range refetches that day's
// visits. The refetch must refresh the layer data without showing a layer
// the user switched off.
async function selectDayOutsideLoadedRange({ visitsEnabled }) {
  const visits = {
    visible: false,
    data: null,
    update(data) {
      this.data = data
    },
    show() {
      this.visible = true
    },
  }
  const controller = {
    settings: { visitsEnabled },
    startDateValue: "2026-10-01T00:00:00",
    endDateValue: "2026-10-02T23:59:59",
    map: { isStyleLoaded: () => true, fitBounds() {} },
    layerManager: { getLayer: (name) => (name === "visits" ? visits : null) },
    api: { fetchVisits: async () => [{ id: 1 }] },
    dataLoader: {
      visitsToGeoJSON: (features) => ({ type: "FeatureCollection", features }),
    },
  }
  const manager = new VisitsManager(controller)

  await manager.onDaySelected({ detail: { date: "2026-10-20" } })
  manager.destroy()

  return visits
}

test("a Timeline day refetch keeps a disabled Visits layer hidden", async () => {
  const visits = await selectDayOutsideLoadedRange({ visitsEnabled: false })

  assert.equal(visits.data.features.length, 1)
  assert.equal(visits.visible, false)
})

test("a Timeline day refetch shows an enabled Visits layer", async () => {
  const visits = await selectDayOutsideLoadedRange({ visitsEnabled: true })

  assert.equal(visits.data.features.length, 1)
  assert.equal(visits.visible, true)
})
