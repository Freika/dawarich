import assert from "node:assert/strict"
import test from "node:test"
import { syncSettingsForm } from "controllers/maps/maplibre/settings_form_sync"

globalThis.CustomEvent ??= class CustomEvent extends Event {
  constructor(type, options = {}) {
    super(type, options)
    this.detail = options.detail ?? null
  }
}

function formHarness(settings, controllerExtras = {}) {
  const fields = new Map()
  const field = (selector) => {
    if (!fields.has(selector)) fields.set(selector, { dataset: {} })
    return fields.get(selector)
  }
  const events = []
  globalThis.document = { dispatchEvent: (event) => events.push(event.type) }
  const visitsSearch = { style: {} }
  const controller = {
    element: { querySelector: field },
    gatedLayersValue: [],
    userPlanValue: "pro",
    hasVisitsToggleTarget: true,
    visitsToggleTarget: { checked: false },
    hasVisitsSearchTarget: true,
    visitsSearchTarget: visitsSearch,
    ...controllerExtras,
  }
  const manager = {
    controller,
    settings,
    syncPointsEditAvailability() {},
    syncTrackColorPicker() {},
    syncTilesFallbackAvailability() {},
    syncStyleDependentToggles() {},
    getDistanceUnit: () => "mi",
    transportation: { syncTransportationSettings() {} },
  }
  syncSettingsForm(manager)
  return { field, events, visitsSearch, controller }
}

test("settings inputs and panels follow the loaded settings", () => {
  const { field, events, visitsSearch, controller } = formHarness({
    visitsEnabled: true,
    splitTracksAtMidnight: true,
    gpsAccuracyThreshold: 30,
    vectorTilesUrl: "https://tiles.example/{z}/{x}/{y}.mvt",
    mapStyle: "dark",
  })

  assert.equal(controller.visitsToggleTarget.checked, true)
  assert.equal(visitsSearch.style.display, "block")
  assert.equal(field('input[name="splitTracksAtMidnight"]').checked, true)
  assert.equal(field('input[name="gpsFilteringEnabled"]').checked, true)
  assert.equal(field('input[name="gpsAccuracyThreshold"]').value, 30)
  assert.equal(field('input[name="minMinutesSpentInCity"]').value, 60)
  assert.equal(field('input[name="distanceUnit"][value="mi"]').checked, true)
  assert.equal(field('select[name="mapStyle"]').value, "dark")
  assert.deepEqual(events, ["map-style:synced", "map-settings:synced"])
})

test("a Lite plan keeps gated layer toggles off", () => {
  const { controller } = formHarness(
    { heatmapEnabled: true, visitsEnabled: true },
    {
      userPlanValue: "lite",
      gatedLayersValue: ["Heatmap"],
      hasHeatmapToggleTarget: true,
      heatmapToggleTarget: { checked: true },
    },
  )

  assert.equal(controller.heatmapToggleTarget.checked, false)
  assert.equal(controller.visitsToggleTarget.checked, true)
})
