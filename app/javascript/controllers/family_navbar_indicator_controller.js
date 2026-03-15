import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["indicator"]
  static values = {
    enabled: Boolean,
  }

  connect() {
    console.log("Family navbar indicator controller connected")
    this.updateIndicator()

    // Listen for location sharing updates
    document.addEventListener(
      "location-sharing:updated",
      this.handleSharingUpdate.bind(this),
    )
    document.addEventListener(
      "location-sharing:expired",
      this.handleSharingExpired.bind(this),
    )
  }

  disconnect() {
    document.removeEventListener(
      "location-sharing:updated",
      this.handleSharingUpdate.bind(this),
    )
    document.removeEventListener(
      "location-sharing:expired",
      this.handleSharingExpired.bind(this),
    )
  }

  handleSharingUpdate(event) {
    // Only update if this is the current user's sharing change
    // (we're only showing the current user's status in navbar)
    this.enabledValue = event.detail.enabled
    this.updateIndicator()
  }

  handleSharingExpired(_event) {
    this.enabledValue = false
    this.updateIndicator()
  }

  updateIndicator() {
    if (!this.hasIndicatorTarget) return

    if (this.enabledValue) {
      this.indicatorTarget.className =
        "tooltip tooltip-bottom w-2 h-2 bg-green-500 rounded-full animate-pulse"
      this.indicatorTarget.dataset.tip =
        "Location is being shared with your family"
    } else {
      this.indicatorTarget.className =
        "tooltip tooltip-bottom w-2 h-2 bg-gray-400 rounded-full"
      this.indicatorTarget.dataset.tip =
        "Location is not being shared with your family"
    }
  }
}
