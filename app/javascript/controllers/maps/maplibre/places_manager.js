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
  async initializePlaceTagFilters() {
    const savedFilters = this.settings.placesTagFilters

    if (savedFilters && savedFilters.length > 0) {
      return this.restoreSavedTagFilters(savedFilters)
    } else {
      return this.enableAllTagsInitial()
    }
  }

  /**
   * Restore saved tag filters
   */
  restoreSavedTagFilters(savedFilters) {
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
    return this.loadPlacesWithTags(savedFilters)
  }

  /**
   * Enable all tags initially
   */
  enableAllTagsInitial() {
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

    SettingsManager.updateSetting("placesTagFilters", allTagIds)
    return this.loadPlacesWithTags(allTagIds)
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
    SettingsManager.updateSetting("placesTagFilters", selectedTags)
    this.loadPlacesWithTags(selectedTags)
  }

  /**
   * Start create place mode
   */
  startCreatePlace() {
    if (
      this.controller.hasSettingsPanelTarget &&
      this.controller.settingsPanelTarget.classList.contains("open")
    ) {
      this.controller.toggleSettings()
    }

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
   * Handle place creation event - reload places and update layer
   */
  async handlePlaceCreated(_event) {
    try {
      const selectedTags = this.getSelectedPlaceTags()

      const places = await this.api.fetchPlaces({
        tag_ids: selectedTags,
      })

      const placesGeoJSON = this.dataLoader.placesToGeoJSON(places)

      console.log(
        "[Maps V2] Converted to GeoJSON:",
        placesGeoJSON.features.length,
        "features",
      )

      const placesLayer = this.layerManager.getLayer("places")
      if (placesLayer) {
        placesLayer.update(placesGeoJSON)
      } else {
        console.warn("[Maps V2] Places layer not found, cannot update")
      }
    } catch (error) {
      console.error("[Maps V2] Failed to reload places:", error)
    }
  }

  /**
   * Handle place update event - reload places and update layer
   */
  async handlePlaceUpdated(event) {
    await this.handlePlaceCreated(event)
  }
}
