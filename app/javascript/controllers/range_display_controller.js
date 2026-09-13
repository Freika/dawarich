import { Controller } from "@hotwired/stimulus"

// Mirrors a range input's current value into an output element (1 decimal).
export default class extends Controller {
  static targets = ["input", "output"]

  connect() {
    this.update()
  }

  update() {
    this.outputTarget.textContent = parseFloat(this.inputTarget.value).toFixed(
      1,
    )
  }
}
