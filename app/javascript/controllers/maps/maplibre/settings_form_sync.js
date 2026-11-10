import { isGatedPlan } from "maps_maplibre/utils/layer_gate"
import { LAYER_NAME_MAP } from "maps_maplibre/utils/settings_manager"

const LAYER_TOGGLES = {
  pointsToggle: "pointsVisible",
  pointsEditToggle: "pointDraggingEnabled",
  heatmapToggle: "heatmapEnabled",
  hexagonsToggle: "hexagonsEnabled",
  visitsToggle: "visitsEnabled",
  photosToggle: "photosEnabled",
  placesToggle: "placesEnabled",
  placeBoundariesToggle: "placeBoundariesEnabled",
  fogToggle: "fogEnabled",
  scratchToggle: "scratchEnabled",
  familyToggle: "familyEnabled",
  tracksToggle: "tracksEnabled",
  flightsToggle: "flightsEnabled",
  anomaliesToggle: "anomaliesEnabled",
}

const capitalize = (name) => name.charAt(0).toUpperCase() + name.slice(1)

/**
 * Seed the settings panel's controls from the loaded settings, then tell the
 * dirty tracker the form is ready.
 */
export function syncSettingsForm(manager) {
  const { controller, settings } = manager
  const gated = isGatedPlan(controller.userPlanValue)
  const field = (selector) => controller.element.querySelector(selector)
  const input = (name) => field(`input[name="${name}"]`)
  const setChecked = (name, checked) => {
    const el = input(name)
    if (el) el.checked = checked
  }

  // The server decides which layers Lite users cannot persist; point
  // editing is off because Lite has no write API.
  const gatedSettingKeys = new Set([
    ...controller.gatedLayersValue.map((layer) => LAYER_NAME_MAP[layer]),
    "pointDraggingEnabled",
  ])
  for (const [targetName, settingKey] of Object.entries(LAYER_TOGGLES)) {
    if (!controller[`has${capitalize(targetName)}Target`]) continue
    controller[`${targetName}Target`].checked =
      gatedSettingKeys.has(settingKey) && gated ? false : settings[settingKey]
  }

  manager.syncPointsEditAvailability()

  setChecked("speed_colored_routes", settings.speedColoredRoutes === true)
  const speedEditor = field('[data-controller~="speed-color-editor"]')
  if (speedEditor)
    speedEditor.dataset.speedColorEditorColorStopsValue =
      settings.speedColorScale

  // Panels that follow their layer toggle.
  for (const [toggle, panel] of [
    ["visitsToggle", "visitsSearch"],
    ["placesToggle", "placesFilters"],
    ["familyToggle", "familyMembersList"],
  ]) {
    if (
      controller[`has${capitalize(toggle)}Target`] &&
      controller[`has${capitalize(panel)}Target`]
    ) {
      controller[`${panel}Target`].style.display = controller[`${toggle}Target`]
        .checked
        ? "block"
        : "none"
    }
  }

  manager.syncTrackColorPicker(settings.trackColor)

  const distanceUnit = field(
    `input[name="distanceUnit"][value="${manager.getDistanceUnit()}"]`,
  )
  if (distanceUnit) distanceUnit.checked = true

  const tilesUrl = input("vectorTilesUrl")
  if (tilesUrl) tilesUrl.value = settings.vectorTilesUrl || ""
  setChecked("tilesFallback", settings.tilesFallback === true)
  manager.style.syncTilesFallbackAvailability()

  // Setting .value doesn't fire "change", so the map-theme-editor controller
  // is told separately; it shows the custom colour block for the style.
  const mapStyleSelect = field('select[name="mapStyle"]')
  if (mapStyleSelect) {
    const style = settings.mapStyle || "light"
    mapStyleSelect.value = style
    manager.style.syncStyleDependentToggles(style)
    document.dispatchEvent(
      new CustomEvent("map-style:synced", { detail: { style } }),
    )
  }

  if (controller.hasGlobeToggleTarget) {
    controller.globeToggleTarget.checked = gated
      ? false
      : settings.globeProjection || false
  }

  for (const name of ["metersBetweenRoutes", "minutesBetweenRoutes"]) {
    const el = input(name)
    if (el) el.value = settings[name]
  }
  setChecked("splitTracksAtMidnight", settings.splitTracksAtMidnight === true)

  const minMinutes = input("minMinutesSpentInCity")
  if (minMinutes) {
    minMinutes.value = settings.minMinutesSpentInCity || 60
    if (controller.hasMinMinutesInCityValueTarget) {
      controller.minMinutesInCityValueTarget.textContent = `${minMinutes.value} min`
    }
  }

  setChecked("gpsFilteringEnabled", settings.gpsFilteringEnabled !== false)
  setChecked(
    "gpsAccuracyFilterEnabled",
    settings.gpsAccuracyFilterEnabled === true,
  )
  const gpsAccuracy = input("gpsAccuracyThreshold")
  if (gpsAccuracy) {
    gpsAccuracy.value = settings.gpsAccuracyThreshold || 100
    if (controller.hasGpsAccuracyThresholdValueTarget) {
      controller.gpsAccuracyThresholdValueTarget.textContent = `${gpsAccuracy.value}m`
    }
  }

  manager.transportation.syncTransportationSettings()

  // All form inputs are seeded now; the dirty tracker snapshots them.
  document.dispatchEvent(new CustomEvent("map-settings:synced"))
}
