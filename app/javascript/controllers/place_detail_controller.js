import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame"]

  open(event) {
    const id = Number(event.detail?.id)
    if (!Number.isSafeInteger(id) || id < 1) return

    this.frameTarget.src = `/places/${id}`
    const url = new URL(window.location.href)
    url.searchParams.set("place_id", id)
    window.history.replaceState(window.history.state, "", url)
  }

  deleted({ detail, params }) {
    if (!detail.success) return

    this.close()
    document.dispatchEvent(
      new CustomEvent("place:deleted", { detail: { id: params.id } }),
    )
  }

  close() {
    this.frameTarget.removeAttribute("src")
    this.frameTarget.replaceChildren()
    const url = new URL(window.location.href)
    url.searchParams.delete("place_id")
    window.history.replaceState(window.history.state, "", url)
  }
}
