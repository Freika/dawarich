import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { gatedToggle } from "maps_maplibre/utils/layer_gate"
import { lazyLoader } from "maps_maplibre/utils/lazy_loader"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

/**
 * Manages main-map layer visibility and lazy loading.
 */
export class LayerVisibilityManager {
  constructor(controller) {
    this.controller = controller
    this.map = controller.map
    this.layerManager = controller.layerManager
    this.settings = controller.settings
    this._anomaliesFetchId = 0
  }

  /**
   * Toggle heatmap visibility
   */
  async toggleHeatmap(event) {
    const toggle = event.target

    const showHeatmap = async () => {
      this.applyHeatmapRenderer(true)
    }

    const hideHeatmap = () => {
      this.applyHeatmapRenderer(false)
    }

    const intercepted = gatedToggle({
      layerName: "Heatmap",
      userPlan: this.controller.userPlanValue,
      toggle,
      showFn: showHeatmap,
      hideFn: hideHeatmap,
      upgradeUrl: this.controller.upgradeUrlValue,
    })
    if (intercepted) return

    const enabled = toggle.checked
    SettingsManager.updateSetting("heatmapEnabled", enabled)
    await this.reapplyPointsRenderer()

    if (enabled) {
      await showHeatmap()
    } else {
      hideHeatmap()
    }
  }

  /**
   * Toggle hexagons visibility
   */
  async toggleHexagons(event) {
    const toggle = event.target

    const intercepted = gatedToggle({
      layerName: "Hexagons",
      userPlan: this.controller.userPlanValue,
      toggle,
      showFn: () => this._showHexagons(),
      hideFn: () => this._hideHexagons(),
      upgradeUrl: this.controller.upgradeUrlValue,
    })
    if (intercepted) return

    const enabled = toggle.checked
    SettingsManager.updateSetting("hexagonsEnabled", enabled)

    if (enabled) {
      await this._showHexagons()
    } else {
      this._hideHexagons()
    }
  }

  async _showHexagons() {
    let hexagonLayer = this.layerManager.getLayer("hexagons")
    if (!hexagonLayer) hexagonLayer = this.layerManager._addHexagonLayer()
    hexagonLayer.show()
    await hexagonLayer.load({
      start_at: this.controller.startDateValue,
      end_at: this.controller.endDateValue,
    })
  }

  _hideHexagons() {
    const hexagonLayer = this.layerManager.getLayer("hexagons")
    if (hexagonLayer) {
      hexagonLayer.dispose()
      hexagonLayer.hide()
    }
  }

  /**
   * Toggle fog of war layer
   */
  async toggleFog(event) {
    const toggle = event.target
    const fogLayer = this.layerManager.getLayer("fog")

    const showFog = async () => {
      if (fogLayer?.mode === "hexagons") {
        fogLayer.toggle(true)
        return
      }
      this.layerManager.getLayer("points-mvt")?.setSourceKeepAlive(true)
      if (fogLayer) fogLayer.toggle(true)
    }

    const hideFog = () => {
      if (fogLayer) fogLayer.toggle(false)
      this.layerManager.getLayer("points-mvt")?.setSourceKeepAlive(false)
    }

    const intercepted = gatedToggle({
      layerName: "Fog of War",
      userPlan: this.controller.userPlanValue,
      toggle,
      showFn: showFog,
      hideFn: hideFog,
      upgradeUrl: this.controller.upgradeUrlValue,
    })
    if (intercepted) return

    const enabled = toggle.checked
    SettingsManager.updateSetting("fogEnabled", enabled)
    await this.reapplyPointsRenderer()

    if (enabled) {
      await showFog()
    } else {
      hideFog()
    }
  }

  /**
   * Toggle scratch map layer
   */
  async toggleScratch(event) {
    const toggle = event.target

    const showScratch = async () => {
      const scratchLayer = this.layerManager.getLayer("scratch")
      if (!scratchLayer) {
        const ScratchLayer = await lazyLoader.loadLayer("scratch")
        const newScratchLayer = new ScratchLayer(this.map, {
          visible: true,
          apiClient: this.controller.api,
          historyScope: () => ({
            startAt: this.controller.startDateValue,
            endAt: this.controller.endDateValue,
          }),
          onTileError: () =>
            Toast.retry(
              translate("messages.failed_to_load_visited_countries"),
              translate("messages.retry"),
              () => newScratchLayer.refresh(),
            ),
          onMembershipError: () =>
            Toast.retry(
              translate("messages.failed_to_load_visited_countries"),
              translate("messages.retry"),
              () => newScratchLayer.retryMembership(),
            ),
        })
        this.layerManager.layers.scratchLayer = newScratchLayer
        try {
          await newScratchLayer.add()
        } catch (error) {
          // A membership failure happens after the source, layers and event
          // listener are installed. Keep that instance for the Retry action;
          // only tear it down if layer installation itself failed.
          if (!this.map.getLayer(newScratchLayer.id)) {
            newScratchLayer.remove()
            if (this.layerManager.layers.scratchLayer === newScratchLayer)
              this.layerManager.layers.scratchLayer = null
          }
          throw error
        }
      } else {
        scratchLayer.show()
      }
    }

    const hideScratch = () => {
      const scratchLayer = this.layerManager.getLayer("scratch")
      if (scratchLayer) scratchLayer.hide()
    }

    const intercepted = gatedToggle({
      layerName: translate("layers.scratch_map"),
      userPlan: this.controller.userPlanValue,
      toggle,
      showFn: showScratch,
      hideFn: hideScratch,
      upgradeUrl: this.controller.upgradeUrlValue,
    })
    if (intercepted) return

    const enabled = toggle.checked
    SettingsManager.updateSetting("scratchEnabled", enabled)
    await this.reapplyPointsRenderer()

    try {
      if (enabled) {
        await showScratch()
      } else {
        hideScratch()
      }
    } catch (error) {
      console.error("Failed to toggle scratch layer:", error)
      Toast.retry(
        translate("messages.failed_to_load_visited_countries"),
        translate("messages.retry"),
        showScratch,
      )
    }
  }

  /**
   * Toggle photos layer
   * Fetches photos from backend on first enable (lazy-load pattern)
   */
  async togglePhotos(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting("photosEnabled", enabled)

    try {
      const photosLayer = this.layerManager.getLayer("photos")

      if (enabled) {
        if (photosLayer && photosLayer.data?.features?.length > 0) {
          photosLayer.show()
        } else {
          // Fetch photos from backend
          this.controller.showProgress()
          this.controller.updateLoadingCounts({
            counts: { photos: 0 },
            isComplete: false,
          })

          const api = this.controller.api
          const dataLoader = this.controller.dataLoader
          const startDate = this.controller.startDateValue
          const endDate = this.controller.endDateValue

          const photosPromise = api.fetchPhotos({
            start_at: startDate,
            end_at: endDate,
          })
          const timeoutPromise = new Promise((_, reject) =>
            setTimeout(() => reject(new Error("Photo fetch timeout")), 15000),
          )
          const photos = await Promise.race([photosPromise, timeoutPromise])
          const photosGeoJSON = dataLoader.photosToGeoJSON(photos)

          this.controller.updateLoadingCounts({
            counts: { photos: photos.length },
            isComplete: true,
          })

          await this.layerManager._addPhotosLayer(photosGeoJSON)

          const newPhotosLayer = this.layerManager.getLayer("photos")
          if (newPhotosLayer) {
            newPhotosLayer.show()
          }
        }
      } else {
        if (photosLayer) {
          photosLayer.hide()
        }
      }
    } catch (error) {
      console.error("Failed to toggle photos layer:", error)
      Toast.error(translate("messages.failed_to_load_photos"))
    }
  }

  /**
   * Toggle tracks layer
   * Fetches tracks from backend on first enable (lazy-load pattern)
   */
  async toggleTracks(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting("tracksEnabled", enabled)

    this.layerManager.getLayer("tracks-mvt")?.setEnabled(enabled)
    this.layerManager.getLayer("tracks")?.toggle(enabled)
    if (!enabled && this.controller.eventHandlers?.selectedTrackFeature) {
      this.controller.eventHandlers.clearTrackSelection()
    }
  }

  /**
   * Toggle AirTrail flights layer visibility (lazy-loads on first enable).
   */
  async toggleFlights(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting("flightsEnabled", enabled)

    try {
      const flightsLayer = this.layerManager.getLayer("flights")

      if (enabled) {
        if (flightsLayer && flightsLayer.data?.features?.length > 0) {
          flightsLayer.show()
        } else {
          const api = this.controller.api
          const flightsGeoJSON = await api.fetchFlights({
            start_at: this.controller.startDateValue,
            end_at: this.controller.endDateValue,
          })

          if (flightsLayer) {
            flightsLayer.update(flightsGeoJSON)
            flightsLayer.show()
          }

          const data = this.controller.mapDataManager?.lastLoadedData
          if (data) data.flightsGeoJSON = flightsGeoJSON
        }
      } else if (flightsLayer) {
        flightsLayer.hide()
      }

      this.controller.mapDataManager?.applyFlightMask()
    } catch (error) {
      console.error("Failed to toggle flights layer:", error)
      Toast.error(translate("messages.failed_to_load_flights"))
    }
  }

  /**
   * Toggle points layer visibility
   */
  async togglePoints(event) {
    SettingsManager.updateSetting("pointsVisible", event.currentTarget.checked)

    await this.reapplyPointsRenderer()
  }

  async reapplyPointsRenderer() {
    const settings = SettingsManager.getSettings()
    const visible = this.controller.hasPointsToggleTarget
      ? this.controller.pointsToggleTarget.checked
      : settings.pointsVisible !== false

    this.layerManager.getLayer("points-mvt")?.toggle(visible)
    this.applyHeatmapRenderer(Boolean(settings.heatmapEnabled))
    this.layerManager
      .getLayer("tracks-mvt")
      ?.setEnabled(settings.tracksEnabled === true)
    const fogTiled = (settings.fogOfWarMode || "points") !== "hexagons"
    this.layerManager.getLayer("fog")?.setTiledSource(fogTiled)
    this.layerManager
      .getLayer("points-mvt")
      ?.setSourceKeepAlive(fogTiled && Boolean(settings.fogEnabled))
    this.controller.settingsController?.syncPointsEditAvailability()
  }

  applyHeatmapRenderer(enabled) {
    this.layerManager.getLayer("points-mvt")?.setHeatmapVisible(enabled)
  }

  async toggleAnomalies(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting("anomaliesEnabled", enabled)
    await this.refreshAnomalies({ enabled })
  }

  async refreshAnomalies({ enabled }) {
    const anomaliesLayer = this.layerManager.getLayer("anomalies")
    if (!anomaliesLayer) return

    if (!enabled) {
      anomaliesLayer.hide()
      return
    }

    const fetchId = ++this._anomaliesFetchId
    this.controller.showProgress()
    this.controller.updateLoadingCounts({
      counts: { anomalies: 0 },
      isComplete: false,
    })

    try {
      const startDate = this.controller.startDateValue
      const endDate = this.controller.endDateValue
      const geoJSON = await anomaliesLayer.fetchAnomalies({
        start_at: startDate,
        end_at: endDate,
      })

      if (fetchId !== this._anomaliesFetchId) return

      this.controller.updateLoadingCounts({
        counts: { anomalies: geoJSON.features.length },
        isComplete: true,
      })

      anomaliesLayer.update(geoJSON)
      anomaliesLayer.show()
    } catch (error) {
      if (fetchId !== this._anomaliesFetchId) return
      console.error("Failed to refresh anomalies layer:", error)
      this.controller.updateLoadingCounts({
        counts: { anomalies: 0 },
        isComplete: true,
      })
      Toast.error(translate("messages.failed_to_load_anomalies"))
    }
  }

  /**
   * Toggle family members layer
   */
  async toggleFamily(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting("familyEnabled", enabled)

    const familyLayer = this.layerManager.getLayer("family")
    if (familyLayer) {
      if (enabled) {
        familyLayer.show()
        // Load family members data
        await this.controller.loadFamilyMembers()
      } else {
        familyLayer.hide()
      }
    }

    // Show/hide the family members list
    if (this.controller.hasFamilyMembersListTarget) {
      this.controller.familyMembersListTarget.style.display = enabled
        ? "block"
        : "none"
    }
  }
}
