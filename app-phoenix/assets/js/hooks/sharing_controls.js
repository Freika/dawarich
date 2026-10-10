import { copyText, manualCopy } from "./clipboard.js"

export const SharingDialog = {
  mounted() {
    this.trigger = document.activeElement
    this.cancel = (event) => {
      event.preventDefault()
      this.pushEvent("sharing_cancel", {})
      this.el.close()
    }
    this.el.addEventListener("cancel", this.cancel)
    this.el.showModal()
  },
  destroyed() {
    this.el.removeEventListener("cancel", this.cancel)
    if (this.el.open) this.el.close()
    if (this.trigger?.isConnected) this.trigger.focus()
    this.trigger = null
  },
}

export const SharingReveal = {
  mounted() {
    this.generation = 0
    this.button = this.el.querySelector("[data-reveal]")
    this.status = this.el.querySelector("[data-status]")
    this.listener = async () => {
      this.clear()
      const generation = this.generation
      this.controller = new AbortController()
      this.button.disabled = true
      try {
        const response = await fetch(this.el.dataset.url, {
          credentials: "same-origin",
          cache: "no-store",
          signal: this.controller.signal,
          headers: {
            "X-CSRF-Token":
              document.querySelector('meta[name="csrf-token"]')?.content || "",
          },
        })
        if (
          !response.ok ||
          response.redirected ||
          !response.headers.get("content-type")?.startsWith("text/plain")
        )
          throw Error("refused")
        const value = await response.text()
        if (generation !== this.generation) return
        const copied = await copyText(
          value,
          () => generation === this.generation,
        )
        if (generation !== this.generation) return
        this.status.textContent = copied
          ? this.el.dataset.copiedLabel
          : this.el.dataset.failedLabel
        if (!copied) this.clearRecovery = manualCopy(this.status, value)
      } catch {
        if (generation === this.generation)
          this.status.textContent = this.el.dataset.failedLabel
      } finally {
        if (generation === this.generation) this.button.disabled = false
      }
    }
    this.button.addEventListener("click", this.listener)
    this.event = this.handleEvent("sharing-clear", () => this.clear())
  },
  clear() {
    this.generation++
    this.controller?.abort()
    this.controller = null
    this.clearRecovery?.()
    this.clearRecovery = null
    this.button.disabled = false
    this.status.textContent = ""
  },
  beforeUpdate() {
    this.clear()
  },
  disconnected() {
    this.clear()
  },
  destroyed() {
    this.clear()
    this.button.removeEventListener("click", this.listener)
    this.removeHandleEvent(this.event)
  },
}

export const SharingPhrase = {
  mounted() {
    this.generation = 0
    this.controller = new AbortController()
    const generation = this.generation
    fetch(this.el.dataset.url, {
      credentials: "same-origin",
      cache: "no-store",
      signal: this.controller.signal,
      headers: {
        "X-CSRF-Token":
          document.querySelector('meta[name="csrf-token"]')?.content || "",
      },
    })
      .then(async (response) => {
        if (
          !response.ok ||
          response.redirected ||
          !response.headers.get("content-type")?.startsWith("text/plain")
        )
          return
        const value = await response.text()
        if (generation === this.generation) this.el.value = value
      })
      .catch(() => {})
    this.event = this.handleEvent("sharing-clear", () => this.clear())
  },
  clear() {
    this.generation++
    this.controller?.abort()
    this.el.value = ""
  },
  beforeUpdate() {
    this.clear()
  },
  disconnected() {
    this.clear()
  },
  destroyed() {
    this.clear()
    this.removeHandleEvent(this.event)
  },
}
