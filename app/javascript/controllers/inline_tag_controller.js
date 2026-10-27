import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "name", "icon", "details"]

  create() {
    this.formTarget.requestSubmit()
  }

  complete(event) {
    if (event.target !== this.formTarget || !event.detail.success) return

    this.nameTarget.value = ""
    this.iconTarget.value = ""
    this.detailsTarget.open = false
  }
}
