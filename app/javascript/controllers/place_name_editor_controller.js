import { Controller } from "@hotwired/stimulus"
import Flash from "./flash_controller"

export default class extends Controller {
  static targets = [
    "display",
    "input",
    "form",
    "editButton",
    "saveButton",
    "cancelButton",
  ]

  connect() {
    this.editing = false
  }

  toggle() {
    if (this.editing) {
      this.cancel()
    } else {
      this.edit()
    }
  }

  edit() {
    this.editing = true
    this.inputTarget.value = this.displayTarget.textContent.trim()
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.editButtonTarget.classList.add("hidden")
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  cancel() {
    this.editing = false
    this.displayTarget.classList.remove("hidden")
    this.formTarget.classList.remove("hidden")
    this.formTarget.classList.add("hidden")
    this.editButtonTarget.classList.remove("hidden")
  }

  async save(event) {
    event.preventDefault()

    const newName = this.inputTarget.value.trim()
    if (!newName || newName === this.displayTarget.textContent.trim()) {
      this.cancel()
      return
    }

    const url = this.formTarget.action
    const csrfToken = document.querySelector("[name='csrf-token']")?.content

    try {
      const response = await fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          Accept: "application/json",
        },
        body: JSON.stringify({ place: { name: newName } }),
      })

      if (!response.ok) {
        const data = await response.json()
        Flash.show("error", data.error || "Failed to update name")
        return
      }

      this.displayTarget.textContent = newName
      this.cancel()
      Flash.show("notice", "Name updated")
    } catch {
      Flash.show("error", "Failed to update name")
    }
  }
}
