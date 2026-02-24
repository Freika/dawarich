import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "radiusInput", "slider", "field", "label"]

  toggleRadius(event) {
    if (event.target.checked) {
      // Enable privacy zone
      this.radiusInputTarget.classList.remove("hidden")

      // Set default value if not already set
      if (!this.fieldTarget.value || this.fieldTarget.value === "") {
        const defaultValue = 1000
        this.fieldTarget.value = defaultValue
        this.sliderTarget.value = defaultValue
        this.labelTarget.textContent = `${defaultValue}m`
      }
    } else {
      // Disable privacy zone
      this.radiusInputTarget.classList.add("hidden")
      this.fieldTarget.value = ""
    }
  }

  updateFromSlider(event) {
    const value = event.target.value
    this.fieldTarget.value = value
    this.labelTarget.textContent = `${value}m`
  }
}
