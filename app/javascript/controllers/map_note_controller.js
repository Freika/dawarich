import { Controller } from "@hotwired/stimulus"

// The map note dialog. The form itself is rendered by the server into the
// turbo frame; this controller only opens and closes the dialog around it.
export default class extends Controller {
  static targets = ["modal", "frame"]
  static values = { newUrl: String }

  connect() {
    this.listeners = {
      "note:new": (event) => this.open(this.newUrlFor(event.detail)),
      "note:edit": (event) => this.open(`/notes/${event.detail.id}/edit`),
      "note:saved": () => this.close(),
      "note:deleted": () => this.close(),
    }
    for (const [type, listener] of Object.entries(this.listeners)) {
      document.addEventListener(type, listener)
    }
  }

  disconnect() {
    for (const [type, listener] of Object.entries(this.listeners)) {
      document.removeEventListener(type, listener)
    }
  }

  newUrlFor({ latitude, longitude, notedAt }) {
    const params = new URLSearchParams({ latitude, longitude })
    if (notedAt) params.set("noted_at", notedAt)
    return `${this.newUrlValue}?${params}`
  }

  open(url) {
    this.frameTarget.innerHTML = ""
    this.frameTarget.src = url
    if (!this.modalTarget.open) this.modalTarget.showModal()
  }

  close(event) {
    event?.preventDefault()
    this.modalTarget.close()
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""
  }
}
