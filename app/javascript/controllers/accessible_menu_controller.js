import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.sync()
  }

  sync() {
    this.element
      .querySelector(":scope > summary")
      ?.setAttribute("aria-expanded", String(this.element.open))
  }
}
