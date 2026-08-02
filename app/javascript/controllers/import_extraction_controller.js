import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { dialogId: String }

  open() {
    const dialog = document.getElementById(this.dialogIdValue)
    if (dialog && typeof dialog.showModal === "function") {
      dialog.showModal()
    }
  }

  close(event) {
    const id = event.params?.dialogId || this.dialogIdValue
    const dialog = document.getElementById(id)
    if (dialog && typeof dialog.close === "function") {
      dialog.close()
    }
  }
}
