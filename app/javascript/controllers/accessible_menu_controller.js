import { Controller } from "@hotwired/stimulus"

// A <details> menu: keeps its summary's aria-expanded in sync and closes the
// menu when a click lands outside it or Escape is pressed.
export default class extends Controller {
  connect() {
    this.closeOnOutsideClick = this.closeOnOutsideClick.bind(this)
    this.closeOnEscape = this.closeOnEscape.bind(this)
    this.sync()
  }

  disconnect() {
    this.stopListening()
  }

  sync() {
    this.summary?.setAttribute("aria-expanded", String(this.element.open))

    // Listen only while open. The toggle event fires after the click that
    // opened the menu has finished, so that click cannot close it again.
    if (this.element.open) {
      document.addEventListener("click", this.closeOnOutsideClick)
      document.addEventListener("keydown", this.closeOnEscape)
    } else {
      this.stopListening()
    }
  }

  closeOnOutsideClick(event) {
    if (this.element.contains(event.target)) return

    this.element.open = false
  }

  closeOnEscape(event) {
    if (event.key !== "Escape") return
    // An open submenu closes first; the next Escape closes this menu.
    if (this.element.querySelector("details[open]")) return

    const hadFocus = this.element.contains(document.activeElement)
    this.element.open = false
    if (hadFocus) this.summary?.focus()
  }

  stopListening() {
    document.removeEventListener("click", this.closeOnOutsideClick)
    document.removeEventListener("keydown", this.closeOnEscape)
  }

  get summary() {
    return this.element.querySelector(":scope > summary")
  }
}
