import { Controller } from "@hotwired/stimulus"

// Hides its element and remembers the dismissal per-browser via localStorage.
// Usage: data-controller="dismissible" data-dismissible-key-value="unique_key"
//        <button data-action="dismissible#dismiss">
export default class extends Controller {
  static values = { key: String }

  connect() {
    if (this.dismissed) this.element.remove()
  }

  dismiss() {
    if (this.keyValue) {
      try {
        localStorage.setItem(this.storageKey, "1")
      } catch (_e) {
        // localStorage unavailable (private mode) — dismissal just won't persist
      }
    }
    this.element.remove()
  }

  get dismissed() {
    if (!this.keyValue) return false
    try {
      return localStorage.getItem(this.storageKey) === "1"
    } catch (_e) {
      return false
    }
  }

  get storageKey() {
    return `dismissed:${this.keyValue}`
  }
}
