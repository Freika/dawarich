import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  close(event) {
    event.preventDefault()

    const frame = this.element.closest("turbo-frame#share-link-modal")
    if (frame) {
      frame.innerHTML = ""
    } else {
      this.element.remove()
    }
  }
}
