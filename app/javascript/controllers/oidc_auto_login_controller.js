import { Controller } from "@hotwired/stimulus"

// Submits the OIDC sign-in form as soon as the page loads. The current history
// entry is first pointed at the sign-in page with auto-login disabled, so
// going back from the identity provider lands on the regular sign-in page.
export default class extends Controller {
  static values = { fallbackUrl: String }

  connect() {
    window.history.replaceState(window.history.state, "", this.fallbackUrlValue)
    // Native submit: the form opts out of Turbo, and submit() also works in
    // browsers without requestSubmit() (Safari < 16).
    this.element.submit()
  }
}
