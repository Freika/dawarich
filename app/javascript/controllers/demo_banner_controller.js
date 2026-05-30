import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["deleteButton", "loadingState", "label"]

  dismiss() {
    this.element.remove()
  }

  confirmDelete(event) {
    const ok = window.confirm(
      "Delete all demo data?\n\n" +
        "This removes the demo points, visits, places, tags, tracks, and the Prague trip.\n\n" +
        "Your real data — anything you've imported, edited, confirmed, or created yourself — will NOT be touched.",
    )
    if (!ok) {
      event.preventDefault()
      return
    }

    this.showLoading()
  }

  showLoading() {
    if (this.hasLoadingStateTarget) {
      this.loadingStateTarget.classList.remove("hidden")
    }
    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.disabled = true
      this.deleteButtonTarget.classList.add("opacity-50", "pointer-events-none")
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = "Removing demo data…"
    }
  }
}
