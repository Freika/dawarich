import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["name", "input", "form"]

  edit() {
    this.nameTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.inputTarget.focus()
  }

  save() {
    this.formTarget.requestSubmit()
  }

  cancel() {
    this.formTarget.classList.add("hidden")
    this.nameTarget.classList.remove("hidden")
  }

  handleEnter(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.save()
    } else if (event.key === "Escape") {
      this.cancel()
    }
  }
}
