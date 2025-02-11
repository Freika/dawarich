import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    timeout: Number
  }

  connect() {
    if (this.timeoutValue) {
      setTimeout(() => {
        this.remove()
      }, this.timeoutValue)
    }
  }

  remove() {
    this.element.classList.add('fade-out')
    setTimeout(() => {
      this.element.remove()

      // Remove the container if it's empty
      const container = document.getElementById('flash-messages')
      if (container && !container.hasChildNodes()) {
        container.remove()
      }
    }, 150)
  }
}
