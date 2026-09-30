import { Controller } from "@hotwired/stimulus"
import Flash from "./flash_controller"

export default class extends Controller {
  static targets = ["display", "editButton", "form", "cancelButton", "checkbox"]

  connect() {
    this.editing = false
  }

  edit() {
    this.editing = true
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.editButtonTarget.classList.add("hidden")
  }

  cancel() {
    this.editing = false
    this.displayTarget.classList.remove("hidden")
    this.formTarget.classList.add("hidden")
    this.editButtonTarget.classList.remove("hidden")
  }

  async save(event) {
    event.preventDefault()

    const checked = this.checkboxTargets
      .filter((cb) => cb.checked)
      .map((cb) => cb.value)

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
        body: JSON.stringify({ place: { tag_ids: checked } }),
      })

      if (!response.ok) {
        const data = await response.json()
        Flash.show("error", data.error || "Failed to update tags")
        return
      }

      // Reload the page to reflect updated tags
      Turbo.visit(window.location.pathname, { action: "replace" })
    } catch {
      Flash.show("error", "Failed to update tags")
    }
  }
}