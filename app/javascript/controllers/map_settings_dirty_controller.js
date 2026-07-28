import { Controller } from "@hotwired/stimulus"

// Tracks unsaved edits in the map settings sections whose fields only
// persist on "Apply Settings" (live-saving controls are simply not inside
// tracked sections, except the expert-mode toggle marked data-dirty-ignore).
// Each tracked <details> gets a badge in its summary with the count of
// changed fields, so edits stay visible after the section is collapsed.
export default class extends Controller {
  static targets = ["section"]

  connect() {
    this.snapshot = {}
    this.takeSnapshot()
    this.onSynced = () => {
      this.takeSnapshot()
      this.refreshBadges()
    }
    // Saved events carry a scope: "form" = the main Apply Settings submit
    // (saves everything except the transportation mode allowlist),
    // "transportation" = that section's own Apply button.
    this.onSaved = (event) => {
      this.markSaved(event.detail?.scope)
      this.refreshBadges()
    }
    document.addEventListener("map-settings:synced", this.onSynced)
    document.addEventListener("map-settings:saved", this.onSaved)
  }

  disconnect() {
    document.removeEventListener("map-settings:synced", this.onSynced)
    document.removeEventListener("map-settings:saved", this.onSaved)
  }

  check() {
    this.refreshBadges()
  }

  takeSnapshot() {
    this.sectionTargets.forEach((section) => {
      Object.assign(this.snapshot, this.readValues(section))
    })
  }

  markSaved(scope) {
    this.sectionTargets.forEach((section) => {
      const sectionScope = section.dataset.dirtyScope || "form"
      if (scope === "transportation" && sectionScope !== "transportation")
        return
      const values = this.readValues(section)
      Object.keys(values).forEach((name) => {
        if (scope === "form" && name === "enabledTransportationModes[]") return
        this.snapshot[name] = values[name]
      })
    })
  }

  refreshBadges() {
    this.sectionTargets.forEach((section) => {
      const badge = section.querySelector("[data-dirty-badge]")
      if (!badge) return

      const changed = this.changedFields(section)
      badge.classList.toggle("hidden", changed.length === 0)
      if (changed.length > 0) {
        badge.textContent = `${changed.length} unsaved`
        badge.dataset.tip = `Changed: ${changed.join(", ")}`
      }
    })
  }

  changedFields(section) {
    const values = this.readValues(section)
    return Object.keys(values)
      .filter((name) => values[name] !== this.snapshot[name])
      .map((name) => this.labelFor(section, name))
  }

  // One serialized value per field name: radios collapse to the checked
  // value, same-name checkbox groups to the sorted checked list.
  readValues(section) {
    const values = {}
    section
      .querySelectorAll("input[name], select[name], textarea[name]")
      .forEach((control) => {
        if (control.hasAttribute("data-dirty-ignore")) return
        const name = control.name
        if (control.type === "radio") {
          if (control.checked) values[name] = control.value
          else if (!(name in values)) values[name] = ""
        } else if (control.type === "checkbox") {
          if (name.endsWith("[]")) {
            const list = (values[name] || "").split(",").filter(Boolean)
            if (control.checked) list.push(control.value)
            values[name] = list.sort().join(",")
          } else {
            values[name] = control.checked ? "1" : "0"
          }
        } else {
          values[name] = control.value
        }
      })
    return values
  }

  labelFor(section, name) {
    const control = section.querySelector(`[name="${CSS.escape(name)}"]`)
    if (!control) return name
    if (name.endsWith("[]")) {
      const legend = control.closest("fieldset")?.querySelector("legend")
      if (legend) return legend.textContent.trim()
    }
    const labelText = control
      .closest(".form-control")
      ?.querySelector(".label-text")
    if (labelText) return labelText.textContent.trim()
    const label = control.closest("label")?.querySelector(".label-text, span")
    return label ? label.textContent.trim() : name
  }
}
