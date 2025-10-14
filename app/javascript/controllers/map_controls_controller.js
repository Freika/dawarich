import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "toggleIcon"]

  toggle() {
    this.panelTarget.classList.toggle("hidden")

    // Toggle the icon between chevron-down and chevron-up
    const currentIcon = this.toggleIconTarget.querySelector('svg')
    const isChevronDown = currentIcon.classList.contains('lucide-chevron-down')

    if (isChevronDown) {
      // Replace with chevron-up
      currentIcon.classList.remove('lucide-chevron-down')
      currentIcon.classList.add('lucide-chevron-up')
      currentIcon.innerHTML = '<path d="m18 15-6-6-6 6"/>'
    } else {
      // Replace with chevron-down
      currentIcon.classList.remove('lucide-chevron-up')
      currentIcon.classList.add('lucide-chevron-down')
      currentIcon.innerHTML = '<path d="m6 9 6 6 6-6"/>'
    }
  }
}
