import { Controller } from "@hotwired/stimulus"

// Sends one Rybbit custom event that the server rendered into the page, then
// removes itself, so a Turbo snapshot of the page cannot send it again.
// The Rybbit script loads deferred, so the event waits for it a short while.
const MAX_ATTEMPTS = 50
const RETRY_MS = 200

export default class extends Controller {
  static values = { name: String, props: Object }

  connect() {
    this.attempts = 0
    this.send()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  send() {
    if (window.rybbit?.event) {
      window.rybbit.event(this.nameValue, this.propsValue)
      this.element.remove()
      return
    }
    this.attempts += 1
    if (this.attempts < MAX_ATTEMPTS) {
      this.timer = setTimeout(() => this.send(), RETRY_MS)
    }
  }
}
