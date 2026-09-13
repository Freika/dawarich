import { Controller } from "@hotwired/stimulus"
import Flash from "./flash_controller"

export default class extends Controller {
  static targets = ["display", "textarea", "form", "editButton", "cancelButton", "saveButton"]

  connect() {
    this.editing = false
  }

  edit() {
    this.editing = true
    this.textareaTarget.value = this.displayTarget.textContent.trim()
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.editButtonTarget.classList.add("hidden")
    this.saveButtonTarget.disabled = false
    this.textareaTarget.focus()
  }

  cancel() {
    this.editing = false
    this.displayTarget.classList.remove("hidden")
    this.formTarget.classList.add("hidden")
    this.editButtonTarget.classList.remove("hidden")
  }

  async save(event) {
    event.preventDefault()

    const newNote = this.textareaTarget.value.trim()
    const originalNote = this.displayTarget.textContent.trim()

    if (newNote === originalNote) {
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
        body: JSON.stringify({ place: { note: newNote } }),
      })

      if (!response.ok) {
        const data = await response.json()
        Flash.show("error", data.error || "Failed to update note")
        return
      }

      this.displayTarget.textContent = newNote
      this.cancel()
      Flash.show("notice", "Note updated")
    } catch {
      Flash.show("error", "Failed to update note")
    }
  }
}
