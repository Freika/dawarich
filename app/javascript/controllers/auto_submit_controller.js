import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  notePointer() {
    this.changedByKeyboard = false
  }

  noteKeyboard(event) {
    if (event.key !== "Tab") this.changedByKeyboard = true
  }

  submit() {
    if (this.changedByKeyboard) {
      this.changedByKeyboard = false
      return
    }
    this.element.requestSubmit()
  }
}
