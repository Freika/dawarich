import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  select(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const icon = button.dataset.icon

    if (this.hasInputTarget && icon) {
      this.inputTarget.value = icon

      // Close the dropdown by removing focus
      const activeElement = document.activeElement
      if (activeElement) {
        activeElement.blur()
      }
    }
  }
}
