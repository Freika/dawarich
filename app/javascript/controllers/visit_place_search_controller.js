import { VisitPlaceSearch } from "maps_maplibre/components/visit_place_search"
import BaseController from "./base_controller"

export default class extends BaseController {
  static values = { visitId: Number, lat: Number, lng: Number, apiKey: String }
  static targets = ["mount"]

  connect() {
    this.boundOnChanged = this.onChanged.bind(this)
    document.addEventListener("visit-place:changed", this.boundOnChanged)
  }

  disconnect() {
    document.removeEventListener("visit-place:changed", this.boundOnChanged)
  }

  toggle() {
    if (!this._search) {
      this._search = new VisitPlaceSearch(
        this.visitIdValue,
        this.latValue,
        this.lngValue,
        this.mountTarget,
        this.apiKeyValue,
      )
    }
    this._search.toggle()
  }

  onChanged(event) {
    if (event.detail?.visitId !== this.visitIdValue) return
    const frame = document.getElementById("timeline-feed-frame")
    if (frame?.reload) frame.reload()
    document.dispatchEvent(new CustomEvent("visit:updated"))
  }
}
