import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"
import maplibregl from "maplibre-gl"
import { ScratchLayer } from "maps_maplibre/layers/scratch_layer"
import { getCurrentTheme } from "maps_maplibre/utils/popup_theme"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

export default class extends Controller {
  static targets = ["dialog", "map", "status"]

  static values = {
    visitedCountries: { type: Array, default: [] },
  }

  connect() {
    this.disconnected = false
  }

  disconnect() {
    this.disconnected = true
    this.scratchLayer?.remove()
    this.map?.remove()
    this.scratchLayer = null
    this.map = null
  }

  open(event) {
    event.preventDefault()
    if (!this.dialogTarget.open) this.dialogTarget.showModal()

    void this.initializeMap()
  }

  async initializeMap() {
    if (this.map) {
      this.map.resize()
      return
    }

    if (this.initializing) return this.initializing

    this.initializing = this.buildMap().finally(() => {
      this.initializing = null
    })

    return this.initializing
  }

  async buildMap() {
    this.showStatus("loading")

    try {
      const style = await getMapStyle(getCurrentTheme())
      if (this.disconnected || !this.dialogTarget.open) return

      const latestCountry = this.visitedCountriesValue.find(
        (country) => country.center,
      )

      this.map = new maplibregl.Map({
        container: this.mapTarget,
        style,
        center: latestCountry?.center || [0, 20],
        zoom: latestCountry ? 3.2 : 1.2,
        minZoom: 1,
        attributionControl: false,
      })

      this.map.addControl(
        new maplibregl.NavigationControl({ showCompass: false }),
        "top-right",
      )
      this.map.addControl(new maplibregl.AttributionControl({ compact: true }))

      await new Promise((resolve) => this.map.once("load", resolve))
      if (this.disconnected) return

      this.scratchLayer = new ScratchLayer(this.map, {
        visitedIsoA3: this.visitedCountriesValue.map(
          (country) => country.iso_a3,
        ),
        onTileError: () => this.showStatus("error"),
      })
      await this.scratchLayer.add()
      this.map.resize()
      this.showStatus("hidden")
    } catch (error) {
      console.error("Stats countries map initialization failed:", error)
      this.showStatus("error")
    }
  }

  showStatus(state) {
    if (!this.hasStatusTarget) return

    this.statusTarget.classList.remove(
      "hidden",
      "loading",
      "loading-spinner",
    )
    this.statusTarget.textContent = ""

    if (state === "loading") {
      this.statusTarget.classList.add("loading", "loading-spinner")
      return
    }

    if (state === "error") {
      this.statusTarget.textContent = translate(
        "messages.failed_to_load_visited_countries",
      )
      return
    }

    this.statusTarget.classList.add("hidden")
  }
}
