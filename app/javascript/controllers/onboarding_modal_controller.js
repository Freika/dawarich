import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "choiceScreen", "importScreen", "trackScreen"]
  static values = {
    showable: Boolean,
    onboardingUrl: String,
    userTrial: Boolean,
    importsCount: Number,
  }

  connect() {
    if (this.showableValue) {
      document.addEventListener("turbo:load", this.handleTurboLoad)
    }
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.handleTurboLoad)
  }

  handleTurboLoad = () => {
    if (this.showableValue) {
      this.checkAndShowModal()
    }
  }

  checkAndShowModal() {
    const MODAL_STORAGE_KEY = "dawarich_onboarding_shown"
    const hasShownModal = localStorage.getItem(MODAL_STORAGE_KEY)

    if (!hasShownModal && this.hasModalTarget) {
      this.modalTarget.showModal()
      localStorage.setItem(MODAL_STORAGE_KEY, "true")
      this.trackEvent("onboarding_shown")

      this.modalTarget.addEventListener("close", () => {
        this.completeOnboarding()
      })
    }
  }

  showImport() {
    this.switchScreen("importScreen")
    this.trackEvent("onboarding_import_selected")
  }

  showTrack() {
    this.switchScreen("trackScreen")
    this.trackEvent("onboarding_track_selected")
  }

  showChoice() {
    this.switchScreen("choiceScreen")
  }

  dismiss() {
    this.modalTarget.close()
  }

  switchScreen(targetName) {
    const screens = ["choiceScreen", "importScreen", "trackScreen"]
    for (const screen of screens) {
      if (
        this[`has${screen.charAt(0).toUpperCase() + screen.slice(1)}Target`]
      ) {
        this[`${screen}Target`].classList.toggle(
          "hidden",
          screen !== targetName,
        )
      }
    }
  }

  completeOnboarding() {
    this.trackEvent("onboarding_completed")

    if (this.onboardingUrlValue) {
      fetch(this.onboardingUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            ?.content,
          "Content-Type": "application/json",
        },
      }).catch((error) => {
        console.warn("[Onboarding] Failed to persist completion:", error)
      })
    }
  }

  trackEvent(eventName) {
    if (typeof window.sa_event === "function") {
      window.sa_event(eventName)
    }
  }
}
