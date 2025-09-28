import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    type: String,
    autoDismiss: Boolean
  }

  connect() {
    this.element.style.animation = 'slideInFromRight 0.3s ease-out forwards'

    if (this.autoDismissValue) {
      this.scheduleDismissal()
    }
  }

  scheduleDismissal() {
    // Auto-dismiss success/notice messages after 5 seconds
    this.dismissTimeout = setTimeout(() => {
      this.dismiss()
    }, 5000)
  }

  dismiss() {
    if (this.dismissTimeout) {
      clearTimeout(this.dismissTimeout)
    }

    this.element.style.animation = 'slideOutToRight 0.3s ease-in forwards'

    setTimeout(() => {
      if (this.element.parentNode) {
        this.element.parentNode.removeChild(this.element)
      }
    }, 300)
  }

  disconnect() {
    if (this.dismissTimeout) {
      clearTimeout(this.dismissTimeout)
    }
  }
}