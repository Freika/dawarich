import { Controller } from "@hotwired/stimulus"
import { panelState } from "maps_maplibre/editing/place_editor_state"

export default class extends Controller {
  static targets = ["frame", "close"]

  connect() {
    this.state = panelState(null, { close: true })
    this.openListener = (event) => this.open(event.detail)
    this.keyListener = (event) => {
      if (event.key === "Escape" && this.state.open) {
        event.preventDefault()
        this.close()
      }
    }
    document.addEventListener("place:open", this.openListener)
    document.addEventListener("keydown", this.keyListener)
  }

  disconnect() {
    document.removeEventListener("place:open", this.openListener)
    document.removeEventListener("keydown", this.keyListener)
  }

  open(detail) {
    this.returnFocus = document.activeElement
    this.state = panelState(this.state, detail)
    this.element.hidden = false
    this.element.classList.remove("place-panel--editing")
    this.frameTarget.src = `/places/${this.state.id}?map_panel=1`
    this.closeTarget.focus()
  }

  loaded() {
    if (!this.state.open) return
    if (this.state.editing) {
      this.frameTarget
        .querySelector('[data-place-editor-target="mapLink"]')
        ?.click()
      this.state.editing = false
    }
  }

  close() {
    this.state = panelState(this.state, { close: true })
    this.element.hidden = true
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""
    document.dispatchEvent(new CustomEvent("place:panel-closed"))
    if (this.returnFocus?.isConnected) this.returnFocus.focus()
  }
}
