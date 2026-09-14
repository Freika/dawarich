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
    "featured",
    "createForm",
    "disableForm",
    "publicLink",
    "sharingButton",
  ]

  open(event) {
    if (this.dialogTarget.open) return
    const wrap = event.currentTarget
    if (!wrap.querySelector(".ach-card")) return
    if (this.hasFeaturedTarget && this.featuredTarget.contains(wrap)) {
      this.featuredKey = wrap.dataset.shareKey
    }
    this.session = {}

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
    this.setBusy(Boolean(this.busy))
    this.hidePanel()
    this.clearError()
    this.dialogTarget.showModal()
  }

  async createPublicLink(event) {
    if (!this.hasFeaturedTarget) return
    const wrap = this.featuredTarget.querySelector(".ach-card-wrap")
    if (!wrap) return
    event.preventDefault()
    this.open({ currentTarget: wrap })
    await this.share()
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

    const { parent, next } = this.origin
    if (parent) {
      parent.insertBefore(this.moved, next?.parentNode === parent ? next : null)
    } else {
      this.moved.remove()
    }
    // Moving the trigger before showModal loses the native return-focus target.
    // Focus it only after reinsertion, without changing the user's scroll position.
    if (this.moved.isConnected) this.moved.focus({ preventScroll: true })
    this.moved = null
    this.origin = null
    this.session = null
    clearTimeout(this.copyTimer)
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
    if (this.busy) return false
    if (this.shared === enabled && (!enabled || this.shareUrl)) return true

    const wrap = this.moved
    const session = this.session
    this.clearError()
    this.setBusy(true)
    try {
      const data = await this.postToggle(enabled, this.toggleUrl)
      if (!data || data.enabled !== enabled || (enabled && !data.url)) {
        if (session === this.session)
          this.showError("Couldn't update sharing. Please try again.")
        return false
      }

      const url = data.url ? absolute(data.url) : null
      // A completed request still belongs to its original card, even if the
      // user has closed the preview or opened a different one while waiting.
      this.persistState(wrap, data.enabled, url)
      if (wrap === this.moved) {
        this.shared = data.enabled
        this.shareUrl = url
      }
      return session === this.session
    } finally {
      this.setBusy(false)
    }
  }

  setBusy(busy) {
    this.busy = busy
    this.toolsTarget.ariaBusy = String(busy)
    for (const button of this.sharingButtonTargets || []) button.disabled = busy
  }

  async postToggle(enabled, url) {
    if (!url) return null
    try {
      const response = await fetch(url, {
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
  persistState(wrap, shared, url) {
    if (!wrap) return
    wrap.dataset.shareShared = String(shared)
    if (shared && url) {
      wrap.dataset.shareUrl = url
    } else {
      delete wrap.dataset.shareUrl
    }
    if (this.featuredKey && wrap.dataset.shareKey === this.featuredKey) {
      if (this.hasCreateFormTarget) this.createFormTarget.hidden = shared
      if (this.hasDisableFormTarget) this.disableFormTarget.hidden = !shared
      if (this.hasPublicLinkTarget) {
        this.publicLinkTarget.hidden = !shared
        this.publicLinkTarget.href = shared ? url : "#"
      }
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

  async copy() {
    const session = this.session
    const value = this.outputTarget.value
    try {
      await navigator.clipboard.writeText(value)
      if (session !== this.session || value !== this.outputTarget.value) return
      this.clearError()
      this.copyBtnTarget.textContent = "Copied"
      clearTimeout(this.copyTimer)
      this.copyTimer = setTimeout(() => {
        if (this.hasCopyBtnTarget) this.copyBtnTarget.textContent = "Copy"
      }, 1500)
    } catch {
      if (session !== this.session) return
      this.showError(
        "Couldn't copy automatically. Select the link or code and copy it manually.",
      )
      this.outputTarget.focus({ preventScroll: true })
      this.outputTarget.select()
    }
  }

  showPanel(label, value) {
    clearTimeout(this.copyTimer)
    this.copyBtnTarget.textContent = "Copy"
    this.panelLabelTarget.textContent = label
    this.outputTarget.value = value
    this.unshareBtnTarget.hidden = !this.shared
    this.panelTarget.hidden = false
    this.outputTarget.focus({ preventScroll: true })
    this.outputTarget.select()
  }

  hidePanel() {
    this.panelTarget.hidden = true
  }

  disconnect() {
    clearTimeout(this.copyTimer)
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}

function absolute(path) {
  return new URL(path, window.location.origin).href
}
