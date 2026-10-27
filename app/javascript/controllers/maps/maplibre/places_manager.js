import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { setPrivacyZonesFingerprint } from "maps_maplibre/utils/tile_freshness"

export class PlacesManager {
  constructor(controller) {
    this.controller = controller
    this.layerManager = controller.layerManager
    this.api = controller.api
    this.dataLoader = controller.dataLoader
    this.settings = controller.settings
  }

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

  togglePlaceBoundaries(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting("placeBoundariesEnabled", enabled)
    this.layerManager.getLayer("places")?.setBoundariesVisible(enabled)
  }

  async initializePlaceTagFilters({ reloadPlaces = true } = {}) {
    const savedFilters = this.settings.placesTagFilters

    if (Array.isArray(savedFilters)) {
      return this.restoreSavedTagFilters(savedFilters, { reloadPlaces })
    } else {
      return this.enableAllTagsInitial({ reloadPlaces })
    }
  }

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

  getSelectedPlaceTags() {
    return Array.from(
      document.querySelectorAll('input[name="place_tag_ids[]"]:checked'),
    ).map((cb) => {
      const value = cb.value
      return value === "untagged" ? value : parseInt(value, 10)
    })
  }

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

  syncEnableAllTagsToggle() {
    if (!this.controller.hasEnableAllPlaceTagsToggleTarget) return

    const tagCheckboxes = document.querySelectorAll(
      'input[name="place_tag_ids[]"]',
    )
    const allChecked = Array.from(tagCheckboxes).every((cb) => cb.checked)

    this.controller.enableAllPlaceTagsToggleTarget.checked = allChecked
  }

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

  async handlePlaceUpdated(event) {
    await this.handlePlaceCreated(event)
  }

  _refreshSavedPlace(placesLayer, place, removedId) {
    const replacement = place
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

  async _reloadPlaces(placesLayer) {
    const selectedTags = this.getSelectedPlaceTags()
    const places = await this.api.fetchPlaces({ tag_ids: selectedTags })
    placesLayer.update(this.dataLoader.placesToGeoJSON(places))
  }

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
