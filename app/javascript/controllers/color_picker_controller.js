import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["picker", "display", "hiddenInput"]

  connect() {
    // Initialize display with current value
    this.updateDisplay()
  }

  updateFromPicker(event) {
    const color = event.target.value

    // Update hidden input
    if (this.hasHiddenInputTarget) {
      this.hiddenInputTarget.value = color
    }

    // Update display
    this.updateDisplay(color)
  }

  updateDisplay(color = null) {
    const colorValue = color || this.pickerTarget.value || '#6ab0a4'

    if (this.hasDisplayTarget) {
      this.displayTarget.style.backgroundColor = colorValue
    }
  }
}
