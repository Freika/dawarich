import { Controller } from "@hotwired/stimulus"
import Flash from "./flash_controller"

export default class extends Controller {
  static targets = [
    "modal",
    "choiceScreen",
    "importScreen",
    "trackScreen",
    "demoButton",
  ]
  static values = {
    showable: Boolean,
    onboardingUrl: String,
    userTrial: Boolean,
    importsCount: Number,
    demoDataUrl: String,
    hasDemoData: Boolean,
    userId: Number,
  }

  connect() {
    if (this.showableValue) {
      document.addEventListener("turbo:load", this.handleTurboLoad)
    }
    this.updateDemoButton()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.handleTurboLoad)
    if (this._handleDialogClose && this.hasModalTarget) {
      this.modalTarget.removeEventListener("close", this._handleDialogClose)
    }
  }

  handleTurboLoad = () => {
    if (this.showableValue) {
      this.checkAndShowModal()
    }
  }

  checkAndShowModal() {
    const storageKey = this.hasUserIdValue
      ? `dawarich_onboarding_shown_${this.userIdValue}`
      : "dawarich_onboarding_shown"
    const hasShownModal = localStorage.getItem(storageKey)

    if (!hasShownModal && this.hasModalTarget) {
      this.modalTarget.showModal()
      localStorage.setItem(storageKey, "true")
      this.trackEvent("onboarding_shown")

      this._handleDialogClose = () => this.completeOnboarding()
      this.modalTarget.addEventListener("close", this._handleDialogClose)
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

  loadDemoData() {
    if (this.hasDemoDataValue) return

    this.trackEvent("onboarding_demo_selected")

    if (this.hasDemoButtonTarget) {
      this.demoButtonTarget.classList.add("opacity-50", "pointer-events-none")
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this.demoDataUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        Accept: "text/html",
      },
      redirect: "follow",
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Server error: ${response.status}`)

        this.modalTarget.close()
        window.Turbo.visit(response.url || window.location.href)
      })
      .catch((error) => {
        console.error("Failed to load demo data:", error)
        if (this.hasDemoButtonTarget) {
          this.demoButtonTarget.classList.remove(
            "opacity-50",
            "pointer-events-none",
          )
        }
        Flash.show("error", "Failed to load demo data. Please try again.")
      })
  }

  updateDemoButton() {
    if (this.hasDemoDataValue && this.hasDemoButtonTarget) {
      this.demoButtonTarget.classList.add("opacity-50", "pointer-events-none")
      const label = this.demoButtonTarget.querySelector("h4")
      if (label) label.textContent = "Demo data already loaded"
    }
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
