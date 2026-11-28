import { Controller } from "@hotwired/stimulus"
import { panelState } from "maps_maplibre/editing/place_editor_state"

export default class extends Controller {
  static targets = ["frame", "close"]

  connect() {
    this.state = panelState(null, { close: true })
    this.listeners = {
      "place:open": (event) => this.open(event.detail),
      "map-panel:closed": () => this.close({ keepClosed: true }),
      "map-panel:tab-changed": (event) => {
        if (event.detail.tab !== "place") this.close({ restore: false })
      },
      keydown: (event) => {
        if (event.key === "Escape" && this.state.open) {
          event.preventDefault()
          this.close()
        }
      },
    }
    for (const [type, listener] of Object.entries(this.listeners))
      document.addEventListener(type, listener)
  }

  disconnect() {
    for (const [type, listener] of Object.entries(this.listeners))
      document.removeEventListener(type, listener)
  }

  get panel() {
    return this.element.closest(".map-control-panel")
  }

  get navigation() {
    return this.application.getControllerForElementAndIdentifier(
      this.panel,
      "map-panel",
    )
  }

  open(detail) {
    if (!this.state.open) this.returnFocus = document.activeElement
    this.state = panelState(this.state, {
      ...detail,
      returnTo: {
        tab:
          this.panel.querySelector("[data-tab-content].active")?.dataset
            .tabContent || "layers",
        open: this.panel.classList.contains("open"),
        scrollTop: this.panel.querySelector(".panel-body").scrollTop,
      },
    })
    this.element.hidden = false
    this.element.classList.remove("place-panel--editing")
    this.panel.classList.remove("place-geometry-editing")
    this.navigation.openTabByName("place")
    this.navigation.titleTarget.textContent =
      this.element.getAttribute("aria-label")
    this.frameTarget.src = `/places/${this.state.id}?map_panel=1`
  }

  loaded() {
    if (!this.state.open) return
    const drawer = this.frameTarget.querySelector(
      "[data-place-editor-place-value]",
    )
    if (!drawer) return
    const place = JSON.parse(drawer.dataset.placeEditorPlaceValue)
    if (place.id !== this.state.id) return
    document.dispatchEvent(
      new CustomEvent("place:panel-loaded", { detail: { place } }),
    )
    if (this.state.editing) {
      this.frameTarget
        .querySelector('[data-place-editor-target="mapLink"]')
        ?.click()
      this.state.editing = false
    }
  }

  close({ restore = true, keepClosed = false } = {}) {
    if (!this.state.open) return
    const returnTo = this.state.returnTo
    this.state = panelState(this.state, { close: true })
    this.element.hidden = true
    this.panel.classList.remove("place-geometry-editing")
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""
    document.dispatchEvent(new CustomEvent("place:panel-closed"))
    if (restore && returnTo) {
      this.navigation.switchToTab(returnTo.tab)
      this.panel.querySelector(".panel-body").scrollTop = returnTo.scrollTop
      if (!returnTo.open && !keepClosed) this.navigation.closePanel()
    }
    if (this.returnFocus?.isConnected) this.returnFocus.focus()
  }
}
