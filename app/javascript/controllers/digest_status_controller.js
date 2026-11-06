import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.timer = setInterval(() => {
      if (!this.element.querySelector("[data-digest-pending]")) return
      if (this.element.hasAttribute("busy")) return
      if (this.element.src) this.element.reload()
      else this.element.src = this.urlValue
    }, 3000)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
