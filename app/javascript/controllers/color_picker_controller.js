import { Controller } from "@hotwired/stimulus"

// Enhanced Color Picker Controller
// Based on RailsBlocks pattern: https://railsblocks.com/docs/color-picker
export default class extends Controller {
  static targets = ["picker", "display", "displayText", "input", "swatch"]
  static values = {
    default: { type: String, default: "#6ab0a4" },
  }

  connect() {
    // Initialize with current value
    const currentColor = this.inputTarget.value || this.defaultValue
    this.updateColor(currentColor, false)
  }

  // Handle color picker (main input) change
  updateFromPicker(event) {
    const color = event.target.value
    this.updateColor(color)
  }

  // Handle swatch click
  selectSwatch(event) {
    event.preventDefault()
    const color = event.currentTarget.dataset.color

    if (color) {
      this.updateColor(color)
    }
  }

  // Update all color displays and inputs
  updateColor(color, updatePicker = true) {
    if (!color) return

    // Update hidden input
    if (this.hasInputTarget) {
      this.inputTarget.value = color
    }

    // Update main color picker
    if (updatePicker && this.hasPickerTarget) {
      this.pickerTarget.value = color
    }

    // Update display
    if (this.hasDisplayTarget) {
      this.displayTarget.style.backgroundColor = color
    }

    // Update display text
    if (this.hasDisplayTextTarget) {
      this.displayTextTarget.textContent = color
    }

    // Update active swatch styling
    this.updateActiveSwatchWithColor(color)

    // Dispatch custom event
    this.dispatch("change", { detail: { color } })
  }

  // Update which swatch appears active
  updateActiveSwatchWithColor(color) {
    if (!this.hasSwatchTarget) return

    // Remove active state from all swatches
    this.swatchTargets.forEach((swatch) => {
      swatch.classList.remove("ring-2", "ring-primary", "ring-offset-2")
    })

    // Find and activate matching swatch
    const matchingSwatch = this.swatchTargets.find(
      (swatch) => swatch.dataset.color?.toLowerCase() === color.toLowerCase(),
    )

    if (matchingSwatch) {
      matchingSwatch.classList.add("ring-2", "ring-primary", "ring-offset-2")
    }
  }
}
