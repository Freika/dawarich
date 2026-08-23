import { Controller } from "@hotwired/stimulus"

// Keeps the current item visible inside a horizontally scrolling strip.
//
// Tab strips are sized by their labels, so a translation that runs longer than
// the English original can push the current tab past the viewport edge — the
// reader lands on a page with no visible indication of where they are. Scroll
// the current tab into view on connect instead of relying on every label being
// short enough to fit.
export default class extends Controller {
  static values = { selector: { type: String, default: ".tab-active" } }

  connect() {
    const current = this.element.querySelector(this.selectorValue)
    if (!current) return
    if (this.element.scrollWidth <= this.element.clientWidth) return

    current.scrollIntoView({
      block: "nearest",
      inline: "center",
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "auto"
        : "smooth",
    })
  }
}
