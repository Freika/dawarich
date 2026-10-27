import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "all", "count", "button", "form", "survivor"]
  static values = { deleteMessage: String }

  connect() {
    this.update()
  }

  toggleAll(event) {
    for (const row of this.rowTargets) row.checked = event.target.checked
    this.update()
  }

  update() {
    const rows = this.rowTargets.filter((row) => row.checked)
    this.countTarget.textContent = rows.length
    this.allTarget.checked =
      rows.length > 0 && rows.length === this.rowTargets.length
    this.allTarget.indeterminate = rows.length > 0 && !this.allTarget.checked
    for (const button of this.buttonTargets) button.disabled = rows.length === 0
    for (const form of this.formTargets) {
      for (const input of form.querySelectorAll("[data-selected-place]"))
        input.remove()
      for (const row of rows) {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = "place_ids[]"
        input.value = row.value
        input.dataset.selectedPlace = "true"
        form.append(input)
      }
    }
    if (this.hasSurvivorTarget) {
      const ids = rows.map((row) => row.value)
      for (const option of this.survivorTarget.options)
        option.disabled = !ids.includes(option.value)
      if (!ids.includes(this.survivorTarget.value))
        this.survivorTarget.value = ids[0] || ""
    }
  }

  confirmDelete(event) {
    const rows = this.rowTargets.filter((row) => row.checked)
    const values = { places: rows.length, visits: 0, geofences: 0, privacy: 0 }
    for (const row of rows) {
      values.visits += Number(row.dataset.visits)
      values.geofences += Number(row.dataset.geofence)
      values.privacy += Number(row.dataset.privacy)
    }
    const message = this.deleteMessageValue.replace(
      /%\{([^}]+)\}/g,
      (_, key) => values[key],
    )
    if (!window.confirm(message)) event.preventDefault()
  }
}
