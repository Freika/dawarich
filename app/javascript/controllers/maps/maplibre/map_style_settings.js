import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { UpgradeBanner } from "maps_maplibre/components/upgrade_banner"
import {
  classifyBasemapUrl,
  styleDocumentFailed,
} from "maps_maplibre/utils/basemap_url"
import {
  applyGlobeProjection,
  globeEnabled,
} from "maps_maplibre/utils/globe_projection"
import { isGatedPlan } from "maps_maplibre/utils/layer_gate"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

/**
 * Basemap settings: style choice, custom tiles URL and fallback, tile
 * categories, POI groups and the globe projection.
 */
export class MapStyleSettings {
  constructor(controller, manager) {
    this.controller = controller
    this.manager = manager
  }

  get settings() {
    return this.manager.settings
  }

  get map() {
    return this.controller.map
  }

  get layerManager() {
    return this.controller.layerManager
  }

  /**
   * Update map style from settings
   */
  async updateMapStyle(event) {
    const styleName = event.target.value
    SettingsManager.updateSetting("mapStyle", styleName)
    await this.applyMapStyle(styleName)
  }

  /**
   * Apply a style to the live map and reload app layers on top.
   * Also called by the map-theme-editor controller to re-apply the
   * custom theme after a preset or token change.
   */
  async applyMapStyle(styleName) {
    this.syncStyleDependentToggles(styleName)
    const style = await getMapStyle(styleName, {
      ...this.mapStyleOptions(),
      vectorTilesUrl: SettingsManager.getSetting("vectorTilesUrl"),
    })

    // Clear layer references
    this.layerManager.clearLayerReferences()

    if (typeof style === "string") {
      this.applyUserStyleUrl(style, styleName)
      return
    }

    this.swapStyle(style)
  }

  // MapLibre only fires style.load when it builds a Style from scratch. Its
  // default path diffs the new document into the live style and stays silent,
  // which would leave the app layers stripped and never re-added, so the
  // rebuild has to be forced.
  swapStyle(style) {
    this.map.once("style.load", () => this.restoreStyleLayers())
    this.map.setStyle(style, { diff: false })
  }

  mapStyleOptions() {
    return {
      hiddenTileCategories:
        SettingsManager.getSetting("hiddenTileCategories") || [],
      disabledPoiGroups: SettingsManager.getSetting("disabledPoiGroups") || [],
      customTheme: SettingsManager.getSetting("customTheme"),
      tilesFallback: SettingsManager.getSetting("tilesFallback") === true,
    }
  }

  // Reload layers after a style change. setStyle replaces the whole style
  // document — including the projection — so globe mode must be restored
  // or every style/theme change silently drops back to mercator.
  async restoreStyleLayers() {
    this.restoreGlobeProjection()
    await this.controller.loadMapData()
    if (
      this.controller.settings?.familyEnabled &&
      !this.controller._disconnected
    ) {
      await this.controller.loadFamilyMembers()
    }
  }

  applyUserStyleUrl(styleUrl, styleName) {
    let settled = false

    const onLoad = () => {
      if (settled) return
      settled = true
      this.map.off("error", onError)
      this.restoreStyleLayers()
    }

    // MapLibre reports every failed request through `error`, tiles included.
    // Only a failure of the style document may discard the user's basemap —
    // one unreachable tile from an otherwise valid style must not.
    const onError = async (event) => {
      if (settled || !styleDocumentFailed(event, styleUrl)) return
      settled = true
      this.map.off("style.load", onLoad)
      this.map.off("error", onError)
      Toast.error(translate("settings.custom_style_load_failed"))
      const fallback = await getMapStyle(styleName, this.mapStyleOptions())
      this.swapStyle(fallback)
    }

    this.map.once("style.load", onLoad)
    this.map.on("error", onError)
    this.map.setStyle(styleUrl, { diff: false })
  }

  restoreGlobeProjection() {
    if (globeEnabled(this.settings.globeProjection)) {
      applyGlobeProjection(this.map)
    }
  }

  /**
   * Toggle globe projection
   * Requires page reload to apply since projection is set at map initialization
   */
  async toggleGlobe(event) {
    const toggle = event.target
    const enabled = toggle.checked

    if (enabled && isGatedPlan(this.controller.userPlanValue)) {
      // Globe can't do a timed preview (requires reload), so just show upgrade prompt
      toggle.checked = false
      UpgradeBanner.show({
        message: translate("messages.globe_view_is_a_pro_feature"),
        upgradeUrl: this.controller.upgradeUrlValue,
        utmContent: "globe_view",
      })
      return
    }

    await SettingsManager.updateSetting("globeProjection", enabled)

    Toast.info(
      translate("messages.globe_view_will_be_applied_after_page_reload"),
    )

    // Prompt user to reload
    if (confirm(translate("settings.confirm_globe_reload"))) {
      window.location.reload()
    }
  }

  /**
   * Base map tile categories / POI groups (moved from /settings/maps).
   * Unchecked toggles form the hidden/disabled lists; the style is
   * rebuilt live so changes are visible immediately.
   */
  async toggleTileCategory() {
    const hidden = this.uncheckedValues("data-tile-category")
    await SettingsManager.updateSetting("hiddenTileCategories", hidden)
    this.applyMapStyle(SettingsManager.getSetting("mapStyle"))
  }

  async togglePoiGroup() {
    const disabled = this.uncheckedValues("data-poi-group")
    await SettingsManager.updateSetting("disabledPoiGroups", disabled)
    this.applyMapStyle(SettingsManager.getSetting("mapStyle"))
  }

  uncheckedValues(attribute) {
    return Array.from(
      this.controller.element.querySelectorAll(`input[${attribute}]`),
    )
      .filter((input) => !input.checked)
      .map((input) => input.getAttribute(attribute))
  }

  /**
   * The Custom style draws no labels or POIs, so their toggles are
   * disabled while it's active, with a tooltip explaining why. A raster or
   * foreign-style basemap carries no Protomaps layers at all, so there every
   * toggle goes dead, not just the unsupported ones — except under a raster
   * basemap with the fallback on, where the default vector stack is composed
   * underneath and the toggles still control what shows through the gaps.
   */
  syncStyleDependentToggles(styleName) {
    const basemap = classifyBasemapUrl(
      SettingsManager.getSetting("vectorTilesUrl"),
    )
    const fallback = SettingsManager.getSetting("tilesFallback") === true
    const foreignBasemap =
      (basemap === "raster" && !fallback) || basemap === "style"
    const custom = styleName === "custom"
    const inputs = this.controller.element.querySelectorAll(
      "input[data-tile-category], input[data-poi-group]",
    )
    inputs.forEach((input) => {
      const unavailable =
        foreignBasemap || (custom && input.dataset.customSupported !== "true")
      input.disabled = unavailable

      const label = input.closest("label")
      if (!label) return
      label.classList.toggle("opacity-40", unavailable)
      label.classList.toggle("tooltip", unavailable)
      label.style.cursor = unavailable ? "not-allowed" : ""
      if (unavailable) {
        label.dataset.tip = foreignBasemap
          ? translate("settings.layer_unavailable_foreign_basemap")
          : translate("settings.layer_unavailable_custom_style")
      } else {
        delete label.dataset.tip
      }
    })
  }

  updateVectorTilesUrl(event) {
    const raw = event.target.value.trim()

    if (!SettingsManager.validVectorTilesUrl(raw)) {
      Toast.error(translate("settings.invalid_tile_url"))
      return
    }

    SettingsManager.updateSetting("vectorTilesUrl", raw || null)
    this.syncTilesFallbackAvailability()
    this.applyMapStyle(SettingsManager.getSetting("mapStyle"))
  }

  async updateTilesFallback(event) {
    await SettingsManager.updateSetting("tilesFallback", event.target.checked)
    this.applyMapStyle(SettingsManager.getSetting("mapStyle"))
  }

  /**
   * The fallback only means something for XYZ tile URLs. A style document
   * replaces the whole style, leaving nothing to draw the default basemap
   * under, and with no custom URL there is nothing to fall back from.
   */
  syncTilesFallbackAvailability() {
    const input = this.controller.element.querySelector(
      'input[name="tilesFallback"]',
    )
    if (!input) return

    const basemap = classifyBasemapUrl(
      SettingsManager.getSetting("vectorTilesUrl"),
    )
    const unavailable = basemap !== "raster" && basemap !== "vector"
    input.disabled = unavailable

    const label = input.closest("label")
    if (!label) return
    label.classList.toggle("opacity-40", unavailable)
    label.classList.toggle("tooltip", unavailable)
    if (unavailable) {
      label.dataset.tip = translate("settings.tiles_fallback_unavailable")
    } else {
      delete label.dataset.tip
    }
  }
}
