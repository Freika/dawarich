import BaseController from "./base_controller"

const ACTIVE_ROWS = ["created", "processing", "deleting"]
  .map((status) => `tr[data-import-status="${status}"]`)
  .join(", ")

// Lives on the imports Turbo frame and reloads it to recover status updates
// broadcast before the imports stream subscribes or reconnects.
export default class extends BaseController {
  connect() {
    super.connect?.()

    const sources = document.querySelectorAll("turbo-cable-stream-source")
    this.observer = new MutationObserver((mutations) => {
      if (mutations.some(({ target }) => target.hasAttribute("connected"))) {
        this.sync()
      }
    })
    sources.forEach((source) => {
      this.observer.observe(source, {
        attributes: true,
        attributeFilter: ["connected"],
      })
    })

    // A row broadcast while the frame is loading can be overwritten by the
    // older response, so load once more after it lands.
    this.markStale = (event) => {
      if (
        this.loading &&
        event.target.getAttribute("target")?.startsWith("import_")
      ) {
        this.stale = true
      }
    }
    this.loaded = () => {
      this.loading = false
      if (this.stale) this.sync()
    }
    document.addEventListener("turbo:before-stream-render", this.markStale)
    this.element.addEventListener("turbo:frame-load", this.loaded)

    if ([...sources].some((source) => source.hasAttribute("connected"))) {
      this.sync()
    }
  }

  disconnect() {
    this.observer.disconnect()
    document.removeEventListener("turbo:before-stream-render", this.markStale)
    this.element.removeEventListener("turbo:frame-load", this.loaded)
  }

  sync() {
    if (!this.element.querySelector(ACTIVE_ROWS)) return

    this.loading = true
    this.stale = false
    // The frame has no src until its first sync; later syncs reload that URL.
    if (this.element.src) this.element.reload()
    else this.element.src = window.location.href
  }
}
