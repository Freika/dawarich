import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]
  static values = { showable: Boolean }

  connect() {
    if (this.showableValue) {
      // Listen for Turbo page load events to show modal after navigation completes
      document.addEventListener("turbo:load", this.handleTurboLoad.bind(this))
    }
  }

  disconnect() {
    // Clean up event listener when controller is removed
    document.removeEventListener("turbo:load", this.handleTurboLoad.bind(this))
  }

  handleTurboLoad() {
    if (this.showableValue) {
      this.checkAndShowModal()
    }
  }

  checkAndShowModal() {
    const MODAL_STORAGE_KEY = "dawarich_onboarding_shown"
    const hasShownModal = localStorage.getItem(MODAL_STORAGE_KEY)

    if (!hasShownModal && this.hasModalTarget) {
      // Show the modal
      this.modalTarget.showModal()

      // Mark as shown in local storage
      localStorage.setItem(MODAL_STORAGE_KEY, "true")

      // Add event listener to handle when modal is closed
      this.modalTarget.addEventListener("close", () => {
        // Modal closed - state already saved
      })
    }
  }
}
