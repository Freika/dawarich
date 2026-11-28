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
// visits. The refetch must leave a Visits layer the user switched off alone:
// no request, no data written into it, and it stays hidden.
async function selectDayOutsideLoadedRange({ visitsAtLoad, visitsOnNow }) {
  let fetches = 0
  const visits = {
    visible: visitsOnNow,
    data: null,
    update(data) {
      this.data = data
    },
    show() {
      this.visible = true
    },
  }
  const controller = {
    settings: { visitsEnabled: visitsAtLoad },
    startDateValue: "2026-10-01T00:00:00",
    endDateValue: "2026-10-02T23:59:59",
    map: { isStyleLoaded: () => true, fitBounds() {} },
    layerManager: { getLayer: (name) => (name === "visits" ? visits : null) },
    api: {
      fetchVisits: async () => {
        fetches++
        return [{ id: 1 }]
      },
    },
    dataLoader: {
      visitsToGeoJSON: (features) => ({ type: "FeatureCollection", features }),
    },
  }
  const manager = new VisitsManager(controller)

  await manager.onDaySelected({ detail: { date: "2026-10-20" } })
  manager.destroy()

  return { visits, fetches }
}

test("a Timeline day refetch leaves a disabled Visits layer alone", async () => {
  const { visits, fetches } = await selectDayOutsideLoadedRange({
    visitsAtLoad: false,
    visitsOnNow: false,
  })

  assert.equal(fetches, 0)
  assert.equal(visits.data, null)
  assert.equal(visits.visible, false)
})

test("a Timeline day refetch respects Visits switched off after load", async () => {
  const { visits, fetches } = await selectDayOutsideLoadedRange({
    visitsAtLoad: true,
    visitsOnNow: false,
  })

  assert.equal(fetches, 0)
  assert.equal(visits.data, null)
  assert.equal(visits.visible, false)
})

test("a Timeline day refetch updates an enabled Visits layer", async () => {
  const { visits, fetches } = await selectDayOutsideLoadedRange({
    visitsAtLoad: true,
    visitsOnNow: true,
  })

  assert.equal(fetches, 1)
  assert.equal(visits.data.features.length, 1)
  assert.equal(visits.visible, true)
})
