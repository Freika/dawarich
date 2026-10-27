import { SettingsManager } from "maps_maplibre/utils/settings_manager"

export class PlacesTagFilters {
  constructor(controller) {
    this.controller = controller
    this.layerManager = controller.layerManager
    this.api = controller.api
    this.dataLoader = controller.dataLoader
    this.settings = controller.settings
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
        this._styleTagCheckbox(checkbox, shouldBeChecked)
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
      this._styleTagCheckbox(checkbox, true)

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
    this.placesRequest = (this.placesRequest || 0) + 1
    const request = this.placesRequest
    try {
      let places = []

      if (tagIds.length > 0) {
        places = await this.api.fetchPlaces({
          tag_ids: tagIds,
          ...(this.settings.showArchivedPlaces
            ? { includeArchived: true }
            : {}),
        })
      }

      if (request !== this.placesRequest) return
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
        this._styleTagCheckbox(checkbox, enableAll)
      }
    })

    const selectedTags = this.getSelectedPlaceTags()
    this.settings.placesTagFilters = selectedTags
    SettingsManager.updateSetting("placesTagFilters", selectedTags)
    this.loadPlacesWithTags(selectedTags)
  }

  _styleTagCheckbox(checkbox, checked) {
    checkbox.checked = checked
    const badge = checkbox.nextElementSibling
    const color = badge.style.borderColor
    badge.classList[checked ? "remove" : "add"]("badge-outline")
    badge.style.backgroundColor = checked ? color : "transparent"
    badge.style.color = checked ? "white" : color
  }
}
