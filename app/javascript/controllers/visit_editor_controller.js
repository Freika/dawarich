import BaseController from "./base_controller"

// Toggles a visit row's inline editor (rename / re-attach place / delete).
// The place search opens together with the panel so nearby candidates are
// visible without another click.
export default class extends BaseController {
  static targets = ["panel", "button"]

  toggle(event) {
    event?.stopPropagation()
    const hidden = this.panelTarget.classList.toggle("hidden")
    if (this.hasButtonTarget)
      this.buttonTarget.setAttribute("aria-expanded", String(!hidden))
    this.syncPlaceSearch(!hidden)
  }

  syncPlaceSearch(opened) {
    const search = this.application.getControllerForElementAndIdentifier(
      this.element,
      "visit-place-search",
    )
    if (!search || opened === search.isOpen) return
    search.toggle()
  }
}
