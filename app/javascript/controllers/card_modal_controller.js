import { Controller } from "@hotwired/stimulus"

// Expands a leaf achievement card to a fullscreen dialog. The card node is
// moved into the dialog (not cloned) so its rendered map survives, then moved
// back on close. Keyed achievements also get Share/Embed controls that reuse
// the existing /achievements/:key/toggle_sharing endpoint (JSON).
export default class extends Controller {
  static targets = [
    "dialog",
    "stage",
    "tools",
    "panel",
    "panelLabel",
    "output",
    "copyBtn",
    "unshareBtn",
    "error",
  ]

  open(event) {
    if (this.dialogTarget.open) return
    const wrap = event.currentTarget
    if (!wrap.querySelector(".ach-card")) return

    // Move the whole wrap (not just the card) so its tilt/holo controller,
    // perspective, and hover behaviour come along and stay live in the dialog.
    this.moved = wrap
    this.origin = { parent: wrap.parentNode, next: wrap.nextSibling }
    // Showcase the card as interactive even when it is a locked achievement,
    // which the grid otherwise keeps inert.
    this.wasLocked = wrap.dataset.achievementCardLockedValue
    wrap.dataset.achievementCardLockedValue = "false"
    this.stageTarget.replaceChildren(wrap)

    this.key = wrap.dataset.shareKey || null
    this.shared = wrap.dataset.shareShared === "true"
    this.shareUrl = wrap.dataset.shareUrl
      ? absolute(wrap.dataset.shareUrl)
      : null
    this.toggleUrl = wrap.dataset.shareToggle || null

    this.toolsTarget.hidden = !this.key
    this.hidePanel()
    this.clearError()
    this.dialogTarget.showModal()
  }

  openOnKey(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.open(event)
    }
  }

  close() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  // Native dialog `close` event — return the card to its place in the grid.
  restore() {
    if (!this.moved || !this.origin) return

    for (const prop of [
      "--rx",
      "--ry",
      "--mx",
      "--my",
      "--fo",
      "--sc",
      "--gl",
    ]) {
      this.moved.style.removeProperty(prop)
    }
    if (this.wasLocked === undefined) {
      this.moved.removeAttribute("data-achievement-card-locked-value")
    } else {
      this.moved.dataset.achievementCardLockedValue = this.wasLocked
    }

    this.origin.parent.insertBefore(this.moved, this.origin.next)
    this.moved = null
    this.origin = null
  }

  async share() {
    if (await this.setSharing(true))
      this.showPanel("Public link", this.shareUrl)
  }

  async embed() {
    if (!(await this.setSharing(true))) return
    const iframe = `<iframe src="${this.shareUrl}" width="360" height="520" style="border:0" title="Dawarich achievement"></iframe>`
    this.showPanel("Embed code", iframe)
  }

  async unshare() {
    if (await this.setSharing(false)) this.hidePanel()
  }

  // Drives sharing to an explicit desired state (not a blind toggle), writes
  // the result back onto the card so a reopen isn't stale, and surfaces
  // failures instead of failing silently. Returns true on success.
  async setSharing(enabled) {
    if (this.shared === enabled) return true

    const data = await this.postToggle(enabled)
    if (!data || data.enabled !== enabled) {
      this.showError("Couldn't update sharing. Please try again.")
      return false
    }

    this.shared = data.enabled
    this.shareUrl = data.url ? absolute(data.url) : null
    this.persistState()
    this.clearError()
    return true
  }

  async postToggle(enabled) {
    if (!this.toggleUrl) return null
    try {
      const response = await fetch(this.toggleUrl, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken,
        },
        body: JSON.stringify({ enabled }),
      })
      return response.ok ? await response.json() : null
    } catch {
      return null
    }
  }

  // Keep the grid card's data-share-* in sync so reopening the modal reflects
  // the latest sharing state rather than the stale server-rendered value.
  persistState() {
    if (!this.moved) return
    this.moved.dataset.shareShared = String(this.shared)
    if (this.shared && this.shareUrl) {
      this.moved.dataset.shareUrl = this.shareUrl
    } else {
      delete this.moved.dataset.shareUrl
    }
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }

  copy() {
    navigator.clipboard?.writeText(this.outputTarget.value)
    this.copyBtnTarget.textContent = "Copied"
    setTimeout(() => {
      if (this.hasCopyBtnTarget) this.copyBtnTarget.textContent = "Copy"
    }, 1500)
  }

  showPanel(label, value) {
    this.panelLabelTarget.textContent = label
    this.outputTarget.value = value
    this.unshareBtnTarget.hidden = !this.shared
    this.panelTarget.hidden = false
    this.outputTarget.focus()
    this.outputTarget.select()
  }

  hidePanel() {
    this.panelTarget.hidden = true
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}

function absolute(path) {
  return new URL(path, window.location.origin).href
}
