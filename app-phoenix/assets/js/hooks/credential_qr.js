export const CredentialQr = {
  mounted() {
    this.generation = 0
    this.clear = () => {
      this.generation += 1
      this.request?.abort()
      this.request = null
      this.el.replaceChildren()
    }
    this.reveal = async () => {
      this.clear()
      const generation = this.generation
      const request = new AbortController()
      this.request = request
      try {
        const response = await fetch("/native/account/qr", {
          credentials: "same-origin",
          headers: {
            "X-CSRF-Token":
              document.querySelector('meta[name="csrf-token"]')?.content || "",
          },
          signal: request.signal,
          cache: "no-store",
        })
        if (!response.ok) return
        const svg = await response.text()
        if (generation !== this.generation || request.signal.aborted) return
        const parsed = new DOMParser().parseFromString(svg, "image/svg+xml")
        if (parsed.documentElement.localName === "svg") {
          this.el.replaceChildren(
            document.importNode(parsed.documentElement, true),
          )
        }
      } catch {
        if (generation === this.generation) this.clear()
      } finally {
        if (this.request === request) this.request = null
      }
    }
    this.onPageReady = () => {
      if (this.el.isConnected && this.el.dataset?.autoReveal) this.reveal()
    }
    globalThis.window?.addEventListener("phx:page-loading-start", this.clear)
    globalThis.window?.addEventListener(
      "phx:page-loading-stop",
      this.onPageReady,
    )
    this.el.addEventListener("dawarich:reveal-qr", this.reveal)
    if (this.el.dataset?.autoReveal) {
      this.handleEvent("refresh-account-credentials", this.reveal)
      this.reveal()
    }
    this.dialog = this.el.closest("dialog")
    this.dialog?.addEventListener("close", this.clear)
  },
  beforeUpdate() {
    this.clear()
  },
  updated() {
    if (this.el.dataset?.autoReveal) this.reveal()
  },
  disconnected() {
    this.clear()
  },
  destroyed() {
    this.clear()
    globalThis.window?.removeEventListener("phx:page-loading-start", this.clear)
    globalThis.window?.removeEventListener(
      "phx:page-loading-stop",
      this.onPageReady,
    )
    this.el.removeEventListener("dawarich:reveal-qr", this.reveal)
    this.dialog?.removeEventListener("close", this.clear)
  },
}
