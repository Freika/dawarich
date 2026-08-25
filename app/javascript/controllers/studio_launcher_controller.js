import { Controller } from "@hotwired/stimulus"

// Opens the poster or video studio from somewhere else on the map page — the
// share hub, for now. Both studios listen on document, and both are portaled
// to <body>, so dismissing the modal this button sits in does not take the
// studio down with it. The modal is dismissed first so the studio is not
// opened behind it.
export default class extends Controller {
  openPoster() {
    this.launch("poster-studio:open")
  }

  openVideo() {
    this.launch("video-studio:open")
  }

  launch(eventName) {
    this.dismissModal()
    document.dispatchEvent(new CustomEvent(eventName))
  }

  dismissModal() {
    const frame = this.element.closest("turbo-frame#share-link-modal")
    if (frame) {
      frame.innerHTML = ""
      return
    }
    this.element.closest(".modal")?.remove()
  }
}
