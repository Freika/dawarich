import BaseController from "./base_controller"

// Recover status updates broadcast before the imports stream subscribes or reconnects.
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
    if ([...sources].some((source) => source.hasAttribute("connected"))) {
      this.sync()
    }
  }

  disconnect() {
    this.observer.disconnect()
  }

  async sync() {
    if (this.syncing) return

    const rows = [...this.element.querySelectorAll("tr[data-import-status]")].filter(
      (row) => ["created", "processing", "deleting"].includes(row.dataset.importStatus),
    )
    if (!rows.length) return

    this.syncing = true
    try {
      const response = await fetch(window.location.href, {
        headers: { Accept: "text/html" },
        credentials: "same-origin",
      })
      if (!response.ok) throw new Error(`Imports sync failed: ${response.status}`)

      const latest = new DOMParser().parseFromString(await response.text(), "text/html")
      rows.forEach((row) => {
        // A newer Turbo broadcast may already have replaced or removed this row.
        if (!row.isConnected || !this.element.contains(row)) return

        const replacement = latest.getElementById(row.id)
        if (replacement) {
          row.replaceWith(document.importNode(replacement, true))
        } else if (row.dataset.importStatus === "deleting") {
          row.remove()
        }
      })
    } catch (error) {
      console.warn("Could not synchronize import statuses", error)
    } finally {
      this.syncing = false
    }
  }
}
