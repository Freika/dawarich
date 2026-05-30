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
    auto: Boolean,
    showable: Boolean,
    onboardingUrl: String,
    userTrial: Boolean,
    importsCount: Number,
    demoDataUrl: String,
    hasDemoData: Boolean,
    userId: Number,
  }

  connect() {
    // Auto-open is gated to the map page (auto=true is set only by the map
    // layout's render). Other pages still render the dialog for the navbar's
    // manual "Getting started" trigger, but never pop it open on load.
    if (this.autoValue && this.showableValue) {
      document.addEventListener("turbo:load", this.handleTurboLoad)
      // The map page is reached via a full (non-Turbo) navigation after
      // signup, where turbo:load never fires — so open from connect() too.
      // Defer one task so a Turbo-swapped <dialog> is ready for showModal();
      // checkAndShowModal is idempotent (localStorage guard) and only marks
      // "shown" once the dialog actually opens, so turbo:load can still retry.
      setTimeout(() => this.checkAndShowModal(), 0)
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
    if (this.autoValue && this.showableValue) {
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
      // If showModal didn't take (called too early during a Turbo render),
      // don't mark it shown — let turbo:load retry instead of silently
      // burning the one-time guard.
      if (!this.modalTarget.open) return

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
