import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "toggleIcon"]

  connect() {
    // Restore panel state from sessionStorage on page load
    const panelState = sessionStorage.getItem("mapControlsPanelState")
    if (panelState === "visible") {
      this.showPanel()
    }
  }

  toggle() {
    const isHidden = this.panelTarget.classList.contains("hidden")

    if (isHidden) {
      this.showPanel()
      sessionStorage.setItem("mapControlsPanelState", "visible")
    } else {
      this.hidePanel()
      sessionStorage.setItem("mapControlsPanelState", "hidden")
    }
  }

  showPanel() {
    this.panelTarget.classList.remove("hidden")

    // Update icon to chevron-up
    const currentIcon = this.toggleIconTarget.querySelector("svg")
    currentIcon.classList.remove("lucide-chevron-down")
    currentIcon.classList.add("lucide-chevron-up")
    currentIcon.innerHTML = '<path d="m18 15-6-6-6 6"/>'
  }

  hidePanel() {
    this.panelTarget.classList.add("hidden")

    // Update icon to chevron-down
    const currentIcon = this.toggleIconTarget.querySelector("svg")
    currentIcon.classList.remove("lucide-chevron-up")
    currentIcon.classList.add("lucide-chevron-down")
    currentIcon.innerHTML = '<path d="m6 9 6 6 6-6"/>'
  }
}
