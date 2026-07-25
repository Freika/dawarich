import { Toast } from "maps_maplibre/components/toast"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

/**
 * Manages places-related operations for Maps V2
 * Including place creation, tag filtering, and layer management
 */
export class PlacesManager {
  constructor(controller) {
    this.controller = controller
    this.layerManager = controller.layerManager
    this.api = controller.api
    this.dataLoader = controller.dataLoader
    this.settings = controller.settings
  }

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

          const loadedPlaces = placesLayer.data?.features?.length || 0
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

  /**
   * Initialize place tag filters (enable all by default or restore saved state)
   */
  async initializePlaceTagFilters({ reloadPlaces = true } = {}) {
    const savedFilters = this.settings.placesTagFilters

    if (Array.isArray(savedFilters)) {
      return this.restoreSavedTagFilters(savedFilters, { reloadPlaces })
    } else {
      return this.enableAllTagsInitial({ reloadPlaces })
    }
  }

  /**
   * Restore saved tag filters
   */
  restoreSavedTagFilters(savedFilters, { reloadPlaces = true } = {}) {
    const tagCheckboxes = document.querySelectorAll(
      'input[name="place_tag_ids[]"]',
    )

    tagCheckboxes.forEach((checkbox) => {
      const value =
        checkbox.value === "untagged"
          ? checkbox.value
          : parseInt(checkbox.value, 10)
      const shouldBeChecked = savedFilters.includes(value)

      if (checkbox.checked !== shouldBeChecked) {
        checkbox.checked = shouldBeChecked

        const badge = checkbox.nextElementSibling
        const color = badge.style.borderColor

        if (shouldBeChecked) {
          badge.classList.remove("badge-outline")
          badge.style.backgroundColor = color
          badge.style.color = "white"
        } else {
          badge.classList.add("badge-outline")
          badge.style.backgroundColor = "transparent"
          badge.style.color = color
        }
      }
    })

    this.syncEnableAllTagsToggle()
    return reloadPlaces
      ? this.loadPlacesWithTags(savedFilters)
      : Promise.resolve()
  }

  /**
   * Enable all tags initially
   */
  enableAllTagsInitial({ reloadPlaces = true } = {}) {
    if (this.controller.hasEnableAllPlaceTagsToggleTarget) {
      this.controller.enableAllPlaceTagsToggleTarget.checked = true
    }

    const tagCheckboxes = document.querySelectorAll(
      'input[name="place_tag_ids[]"]',
    )
    const allTagIds = []

    tagCheckboxes.forEach((checkbox) => {
      checkbox.checked = true

      const badge = checkbox.nextElementSibling
      const color = badge.style.borderColor
      badge.classList.remove("badge-outline")
      badge.style.backgroundColor = color
      badge.style.color = "white"

      const value =
        checkbox.value === "untagged"
          ? checkbox.value
          : parseInt(checkbox.value, 10)
      allTagIds.push(value)
    })

    this.settings.placesTagFilters = allTagIds
    SettingsManager.updateSetting("placesTagFilters", allTagIds)
    return reloadPlaces ? this.loadPlacesWithTags(allTagIds) : Promise.resolve()
  }

  /**
   * Get selected place tag IDs
   */
  getSelectedPlaceTags() {
    return Array.from(
      document.querySelectorAll('input[name="place_tag_ids[]"]:checked'),
    ).map((cb) => {
      const value = cb.value
      return value === "untagged" ? value : parseInt(value, 10)
    })
  }

  /**
   * Filter places by selected tags
   */
  filterPlacesByTags(event) {
    const badge = event.target.nextElementSibling
    const color = badge.style.borderColor

    if (event.target.checked) {
      badge.classList.remove("badge-outline")
      badge.style.backgroundColor = color
      badge.style.color = "white"
    } else {
      badge.classList.add("badge-outline")
      badge.style.backgroundColor = "transparent"
      badge.style.color = color
    }

    this.syncEnableAllTagsToggle()

    const checkedTags = this.getSelectedPlaceTags()
    this.settings.placesTagFilters = checkedTags
    SettingsManager.updateSetting("placesTagFilters", checkedTags)
    this.loadPlacesWithTags(checkedTags)
  }

  /**
   * Sync "Enable All Tags" toggle with individual tag states
   */
  syncEnableAllTagsToggle() {
    if (!this.controller.hasEnableAllPlaceTagsToggleTarget) return

    const tagCheckboxes = document.querySelectorAll(
      'input[name="place_tag_ids[]"]',
    )
    const allChecked = Array.from(tagCheckboxes).every((cb) => cb.checked)

    this.controller.enableAllPlaceTagsToggleTarget.checked = allChecked
  }

  /**
   * Load places filtered by tags
   */
  async loadPlacesWithTags(tagIds = []) {
    try {
      let places = []

      if (tagIds.length > 0) {
        places = await this.api.fetchPlaces({ tag_ids: tagIds })
      }

      const placesGeoJSON = this.dataLoader.placesToGeoJSON(places)

      const placesLayer = this.layerManager.getLayer("places")
      if (placesLayer) {
        placesLayer.update(placesGeoJSON)
      }
    } catch (error) {
      console.error("[Maps V2] Failed to load places:", error)
    }
  }

  /**
   * Toggle all place tags on/off
   */
  toggleAllPlaceTags(event) {
    const enableAll = event.target.checked
    const tagCheckboxes = document.querySelectorAll(
      'input[name="place_tag_ids[]"]',
    )

    tagCheckboxes.forEach((checkbox) => {
      if (checkbox.checked !== enableAll) {
        checkbox.checked = enableAll

        const badge = checkbox.nextElementSibling
        const color = badge.style.borderColor

        if (enableAll) {
          badge.classList.remove("badge-outline")
          badge.style.backgroundColor = color
          badge.style.color = "white"
        } else {
          badge.classList.add("badge-outline")
          badge.style.backgroundColor = "transparent"
          badge.style.color = color
        }
      }
    })

    const selectedTags = this.getSelectedPlaceTags()
    this.settings.placesTagFilters = selectedTags
    SettingsManager.updateSetting("placesTagFilters", selectedTags)
    this.loadPlacesWithTags(selectedTags)
  }

  /**
   * Start create place mode
   */
  startCreatePlace() {
    this.controller.map.getCanvas().style.cursor = "crosshair"
    Toast.info("Click on the map to place a place")

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
   * place instead of re-pulling the whole collection from the backend. A full
   * fetch happens only on first load, when the layer has no data yet.
   */
  async handlePlaceCreated(event) {
    try {
      const placesLayer = this.layerManager.getLayer("places")
      if (!placesLayer) {
        console.warn("[Maps V2] Places layer not found, cannot update")
        return
      }

      const place = event?.detail?.place
      if (place && placesLayer.data?.features?.length) {
        this._upsertPlaceFeature(placesLayer, place)
      } else {
        await this._reloadPlaces(placesLayer)
      }

      this._ensurePlacesVisible(placesLayer)
    } catch (error) {
      console.error("[Maps V2] Failed to update places:", error)
    }
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
  _upsertPlaceFeature(placesLayer, place) {
    const feature = this.dataLoader.placesToGeoJSON([place]).features[0]
    if (!feature) return

    const existing = placesLayer.data?.features || []
    const index = existing.findIndex((f) => f.properties?.id === place.id)
    const features =
      index >= 0
        ? existing.map((f, i) => (i === index ? feature : f))
        : [...existing, feature]

    placesLayer.update({ type: "FeatureCollection", features })
  }

  /**
   * Fetch the full places collection (respecting active tag filters) and
   * replace the layer's data. Used for the initial load only.
   */
  async _reloadPlaces(placesLayer) {
    const selectedTags = this.getSelectedPlaceTags()
    const places = await this.api.fetchPlaces({ tag_ids: selectedTags })
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
