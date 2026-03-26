import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import {
  getMapStyle,
  POI_GROUPS,
  TILE_LAYER_CATEGORIES,
} from "maps_maplibre/utils/style_manager"

export default class extends Controller {
  static targets = ["mapContainer", "categoryToggles", "poiToggles"]
  static values = {
    style: { type: String, default: "light" },
    hiddenCategories: { type: Array, default: [] },
    disabledPoiGroups: { type: Array, default: [] },
  }

  connect() {
    this.initializeMap()
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  async initializeMap() {
    const style = await getMapStyle(this.styleValue, {
      hiddenTileCategories: this.hiddenCategoriesValue,
      disabledPoiGroups: this.disabledPoiGroupsValue,
    })

    this.map = new maplibregl.Map({
      container: this.mapContainerTarget,
      style,
      center: [13.405, 52.52],
      zoom: 13,
      attributionControl: false,
    })

    this.map.addControl(
      new maplibregl.NavigationControl({ showCompass: false }),
      "top-right",
    )
  }

  // --- Tile layer category toggles ---

  toggleCategory(event) {
    const category = event.target.dataset.category
    const visible = event.target.checked

    this.setCategoryVisibility(category, visible)
    this.updateHiddenInput()
  }

  setCategoryVisibility(category, visible) {
    const layers = TILE_LAYER_CATEGORIES[category]
    if (!layers || !this.map) return

    const visibility = visible ? "visible" : "none"
    for (const layerId of layers) {
      if (this.map.getLayer(layerId)) {
        this.map.setLayoutProperty(layerId, "visibility", visibility)
      }
    }
  }

  updateHiddenInput() {
    const hidden = []
    const checkboxes = this.categoryTogglesTarget.querySelectorAll(
      'input[type="checkbox"][data-category]',
    )
    for (const cb of checkboxes) {
      if (!cb.checked) {
        hidden.push(cb.dataset.category)
      }
    }

    const input = this.element.querySelector(
      'input[name="maps[hidden_tile_categories]"]',
    )
    if (input) {
      input.value = JSON.stringify(hidden)
    }
  }

  // --- POI group toggles ---

  togglePoiGroup() {
    this.updatePoiFilter()
    this.updateDisabledPoiInput()
  }

  updatePoiFilter() {
    if (!this.map) return

    const kinds = this.collectEnabledPoiKinds()
    const layer = this.map.getStyle().layers.find((l) => l.id === "pois")
    if (!layer) return

    const zoomFilter = layer.filter?.[2] || [">=", ["zoom"], 0]
    this.map.setFilter("pois", [
      "all",
      ["in", ["get", "kind"], ["literal", kinds]],
      zoomFilter,
    ])
  }

  collectEnabledPoiKinds() {
    const kinds = []
    const checkboxes = this.poiTogglesTarget.querySelectorAll(
      'input[type="checkbox"][data-poi-group]',
    )
    for (const cb of checkboxes) {
      if (cb.checked) {
        const group = POI_GROUPS[cb.dataset.poiGroup]
        if (group) kinds.push(...group.kinds)
      }
    }
    return kinds
  }

  updateDisabledPoiInput() {
    const disabled = []
    const checkboxes = this.poiTogglesTarget.querySelectorAll(
      'input[type="checkbox"][data-poi-group]',
    )
    for (const cb of checkboxes) {
      if (!cb.checked) {
        disabled.push(cb.dataset.poiGroup)
      }
    }

    const input = this.element.querySelector(
      'input[name="maps[disabled_poi_groups]"]',
    )
    if (input) {
      input.value = JSON.stringify(disabled)
    }
  }
}
