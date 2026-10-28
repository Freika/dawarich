import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"

export default class extends Controller {
  static values = { place: Object, maxRadius: Number }
  static targets = [
    "mapLink",
    "mapForm",
    "latitude",
    "longitude",
    "radius",
    "radiusLabel",
  ]

  connect() {
    this.changeListener = (event) => {
      if (event.detail.id !== this.placeValue.id) return
      this.latitudeTarget.value = event.detail.latitude
      this.longitudeTarget.value = event.detail.longitude
      this.radiusTarget.value = event.detail.visit_radius
      this.radiusLabelTarget.textContent = `${translate("map_info.visit_radius")}: ${event.detail.visit_radius} m`
    }
    document.addEventListener("place:geometry-changed", this.changeListener)
    if (this.element.closest(".place-panel")) {
      this.element
        .closest(".place-panel")
        .classList.remove("place-panel--editing")
      this.element
        .closest(".map-control-panel")
        .classList.remove("place-geometry-editing")
      this.element.dispatchEvent(
        new CustomEvent("place:editor-ready", { bubbles: true }),
      )
    }
  }

  disconnect() {
    document.removeEventListener("place:geometry-changed", this.changeListener)
  }

  edit(event) {
    const panel = this.element.closest(".place-panel")
    if (!panel) return
    event.preventDefault()
    panel.classList.add("place-panel--editing")
    panel.closest(".map-control-panel").classList.add("place-geometry-editing")
    this.mapFormTarget.classList.remove("hidden")
    this.mapLinkTarget.classList.add("hidden")
    document.dispatchEvent(
      new CustomEvent("place:map-edit", {
        detail: { place: this.placeValue, maximum: this.maxRadiusValue },
      }),
    )
  }

  cancel() {
    this.element
      .closest(".map-control-panel")
      ?.classList.remove("place-geometry-editing")
    this.element
      .closest(".place-panel")
      ?.classList.remove("place-panel--editing")
    this.mapFormTarget.classList.add("hidden")
    this.mapLinkTarget.classList.remove("hidden")
    document.dispatchEvent(new CustomEvent("place:map-cancel"))
  }
}
