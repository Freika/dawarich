import { loadLastView, saveView } from "maps_maplibre/utils/map_view_store"
import { syncSidebarLayout } from "maps_maplibre/utils/sidebar_layout"
import { MapInitializer } from "./map_initializer"

/** Whether the browser can create a WebGL2 context. */
export function isWebGLSupported() {
  try {
    const canvas = document.createElement("canvas")
    const gl = canvas.getContext("webgl2")
    // Hand the probe's context back at once: iOS caps live WebGL contexts,
    // and this one would otherwise linger until GC on every day switch.
    gl?.getExtension("WEBGL_lose_context")?.loseContext()
    return !!gl
  } catch {
    return false
  }
}

export function showWebGLError(controller) {
  controller.containerTarget.classList.add("hidden")
  controller.webglErrorTarget.classList.remove("hidden")
}

export async function loadViewSettings(controller) {
  await controller.settingsController.loadSettings()
  // A city card opens the map with fog on for this view only; the copy
  // keeps the forced layer out of the stored settings.
  controller.settings = controller.hasExplorationBoundsValue
    ? { ...controller.settingsController.settings, fogEnabled: true }
    : controller.settingsController.settings
  controller.settings.timezone = controller.timezoneValue
}

/**
 * Create the MapLibre map in the container and store it as controller.map.
 * Leaves controller.map unset when the browser refuses a WebGL context or
 * the controller disconnected while the style loaded.
 */
export async function initializeMap(controller) {
  syncSidebarLayout(
    controller.settingsPanelTarget,
    controller.containerTarget,
    true,
  )
  // Reopen at the user's last viewport instead of the zoomed-out globe.
  // When the date range has data, fitBounds overrides this; when it has
  // none, the map stays on the last-known view rather than the world.
  const lastView = loadLastView(controller.apiKeyValue)

  let map
  try {
    map = await MapInitializer.initialize(
      controller.containerTarget,
      {
        mapStyle: controller.settings.mapStyle,
        globeProjection: controller.settings.globeProjection,
        hiddenTileCategories: controller.settings.hiddenTileCategories || [],
        disabledPoiGroups: controller.settings.disabledPoiGroups || [],
        customTheme: controller.settings.customTheme,
        vectorTilesUrl: controller.settings.vectorTilesUrl,
        tilesFallback: controller.settings.tilesFallback === true,
        ...(lastView ? { center: lastView.center, zoom: lastView.zoom } : {}),
      },
      controller.apiKeyValue,
    )
  } catch (error) {
    // The isWebGLSupported() probe passes, yet the browser can still refuse
    // the map its own context, e.g. iOS Safari past its WebGL context limit.
    if (error?.name !== "GPUInitializationError") throw error
    console.warn("[Maps V2] WebGL context refused:", error)
    showWebGLError(controller)
    return
  }

  // The controller may have disconnected while the style was loading (e.g.
  // fast Turbo navigation). Tear the map down instead of attaching a listener
  // to an orphaned instance that disconnect() can no longer reach.
  if (controller._disconnected) {
    map.remove()
    return
  }

  controller.map = map
  controller._persistView = () =>
    saveView(controller.map, controller.apiKeyValue)
  controller.map.on("moveend", controller._persistView)
}
