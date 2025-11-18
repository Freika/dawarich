import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "hiddenInput"]

  select(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const icon = button.dataset.icon

    if (icon) {
      // Update the display
      if (this.hasDisplayTarget) {
        this.displayTarget.textContent = icon
      }

      // Update the hidden input
      if (this.hasHiddenInputTarget) {
        this.hiddenInputTarget.value = icon
      }

      // Close the dropdown by removing focus
      const activeElement = document.activeElement
      if (activeElement) {
        activeElement.blur()
      }
    }
  }
}
