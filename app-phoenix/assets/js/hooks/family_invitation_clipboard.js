export const FamilyInvitationClipboard = {
  mounted() {
    this.generation = 0
    this.copy = async (event) => {
      event.preventDefault()
      this.clear()
      const generation = this.generation
      const controller = new AbortController()
      this.controller = controller
      this.el.disabled = true
      try {
        const response = await fetch(this.el.dataset.revealPath, {
          credentials: "same-origin",
          cache: "no-store",
          signal: controller.signal,
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
        const capability = await response.text()
        if (generation !== this.generation) return
        await navigator.clipboard.writeText(capability)
        if (generation === this.generation)
          this.report(this.el.dataset.copiedLabel)
      } catch {
        if (generation === this.generation)
          this.report(this.el.dataset.failedLabel)
      } finally {
        if (generation === this.generation) this.el.disabled = false
      }
    }
    this.el.addEventListener("click", this.copy)
  },
  beforeUpdate() {
    this.clear()
  },
  disconnected() {
    this.clear()
  },
  destroyed() {
    this.clear()
    this.el.removeEventListener("click", this.copy)
  },
  clear() {
    this.generation++
    this.controller?.abort()
    this.controller = null
    this.el.disabled = false
    this.report("")
  },
  report(text) {
    const status = document.getElementById(this.el.dataset.statusId)
    if (status) status.textContent = text
  },
}
