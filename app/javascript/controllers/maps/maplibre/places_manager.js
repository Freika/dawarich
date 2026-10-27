import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { setPrivacyZonesFingerprint } from "maps_maplibre/utils/tile_freshness"
import { PlacesTagFilters } from "./places_tag_filters"

/**
 * Manages places-related operations for Maps V2
 * Including place creation, tag filtering, and layer management
 */
export class PlacesManager extends PlacesTagFilters {
  /**
   * Toggle places layer
   */
  async togglePlaces(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting("placesEnabled", enabled)

    const placesLayer = this.layerManager.getLayer("places")
    if (placesLayer) {
      if (enabled) {
        placesLayer.show()
        if (this.controller.hasPlacesFiltersTarget) {
          this.controller.placesFiltersTarget.style.display = "block"
        }

        // Show progress badge if layer has no data yet (initial load)
        if (!placesLayer.data?.features?.length) {
          this.controller.showProgress()
          this.controller.updateLoadingCounts({
            counts: { places: 0 },
            isComplete: false,
          })

          await this.initializePlaceTagFilters()

          const loadedPlaces =
            placesLayer.data?.features?.filter(
              (feature) => feature.properties?.featureKind === "center",
            ).length || 0
          this.controller.updateLoadingCounts({
            counts: { places: loadedPlaces },
            isComplete: true,
          })
        } else {
          this.initializePlaceTagFilters()
        }
      } else {
        placesLayer.hide()
        if (this.controller.hasPlacesFiltersTarget) {
          this.controller.placesFiltersTarget.style.display = "none"
        }
      }
    }
  }

  toggleArchivedPlaces(event) {
    this.settings.showArchivedPlaces = event.target.checked
    return this.loadPlacesWithTags(this.getSelectedPlaceTags())
  }

  togglePlaceBoundaries(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting("placeBoundariesEnabled", enabled)
    this.layerManager.getLayer("places")?.setBoundariesVisible(enabled)
  }

  /**
   * Start create place mode
   */
  startCreatePlace() {
    this.controller.map.getCanvas().style.cursor = "crosshair"
    Toast.info(translate("messages.click_on_the_map_to_place_a_place"))

    this.handleCreatePlaceClick = (e) => {
      const { lng, lat } = e.lngLat

      document.dispatchEvent(
        new CustomEvent("place:create", {
          detail: { latitude: lat, longitude: lng },
        }),
      )

      this.controller.map.getCanvas().style.cursor = ""
    }

    this.controller.map.once("click", this.handleCreatePlaceClick)
  }

  /**
   * Handle place creation/update events. The event carries the saved place,
   * so when the layer already holds data we upsert that single feature in
   * place instead of re-pulling the whole collection from the backend.
   */
  async handlePlaceCreated(event) {
    try {
      const placesLayer = this.layerManager.getLayer("places")
      if (!placesLayer) {
        console.warn("[Maps V2] Places layer not found, cannot update")
        return
      }

      const place = event?.detail?.place
      const removedId = event?.detail?.removedId
      if (place || removedId) {
        this._refreshSavedPlace(placesLayer, place, removedId)
      } else {
        await this._reloadPlaces(placesLayer)
      }

      this._ensurePlacesVisible(placesLayer)
      await this._refreshPrivacyZones()
    } catch (error) {
      console.error("[Maps V2] Failed to update places:", error)
    }
  }

  /**
   * A saved place can add, move or drop a privacy zone. When the zone
   * fingerprint changes, every masked layer is reloaded under the new zones,
   * and the current position is hidden until the next live point because
   * it may now sit inside a zone.
   */
  async _refreshPrivacyZones() {
    const { fingerprint, failed } = await this.api.fetchPrivacyZones()
    if (failed || !setPrivacyZonesFingerprint(fingerprint)) return

    this.layerManager.getLayer("recentPoint")?.clear()
    this.controller.element?.removeAttribute(
      "data-maps--maplibre-current-position-value",
    )
    this.layerManager.getLayer("points-mvt")?.refresh()
    this.layerManager.getLayer("tracks-mvt")?.refresh()
    await this.controller.loadMapData({ showLoading: false, fitBounds: false })
  }

  /**
   * Handle place update event - same upsert path as creation.
   */
  async handlePlaceUpdated(event) {
    await this.handlePlaceCreated(event)
  }

  /**
   * Append or replace a single place feature on the layer without touching
   * the backend. Replaces by id when the place is already present (edit).
   */
  _refreshSavedPlace(placesLayer, place, removedId) {
    const replacement =
      place && (!place.archived || this.settings.showArchivedPlaces)
        ? this.dataLoader.placesToGeoJSON([place]).features
        : []
    const existing = placesLayer.data?.features || []
    const features = [
      ...existing.filter(
        (feature) => feature.properties?.id !== (place?.id ?? removedId),
      ),
      ...replacement,
    ]
    placesLayer.update({ type: "FeatureCollection", features })
  }

  /**
   * Fetch the full places collection (respecting active tag filters) and
   * replace the layer's data. Used for the initial load only.
   */
  async _reloadPlaces(placesLayer) {
    const selectedTags = this.getSelectedPlaceTags()
    const places = await this.api.fetchPlaces({
      tag_ids: selectedTags,
      ...(this.settings.showArchivedPlaces ? { includeArchived: true } : {}),
    })
    placesLayer.update(this.dataLoader.placesToGeoJSON(places))
  }

  /**
   * Auto-enable the layer if it was off (the default), otherwise a newly
   * created place would land in a hidden layer and never appear.
   */
  _ensurePlacesVisible(placesLayer) {
    if (placesLayer.visible) return

    placesLayer.show()
    SettingsManager.updateSetting("placesEnabled", true)
    if (this.controller.hasPlacesToggleTarget) {
      this.controller.placesToggleTarget.checked = true
    }
    if (this.controller.hasPlacesFiltersTarget) {
      this.controller.placesFiltersTarget.style.display = "block"
    }
  }
}
