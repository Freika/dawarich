import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "enableToggle",
    "expirationSettings",
    "sharingLink",
    "form",
    "expirationSelect",
  ]

  toggleSharing() {
    const isEnabled = this.enableToggleTarget.checked

    if (isEnabled) {
      this.expirationSettingsTarget.classList.remove("hidden")
    } else {
      this.expirationSettingsTarget.classList.add("hidden")
      if (this.hasSharingLinkTarget) {
        this.sharingLinkTarget.value = ""
      }
    }

    this.formTarget.requestSubmit()
  }

  expirationChanged() {
    if (this.enableToggleTarget.checked) {
      this.formTarget.requestSubmit()
    }
  }

  async copyLink() {
    if (!this.hasSharingLinkTarget) return

    try {
      await navigator.clipboard.writeText(this.sharingLinkTarget.value)

      const button = this.sharingLinkTarget.nextElementSibling
      const originalText = button.innerHTML
      button.innerHTML = "Link Copied!"
      button.classList.add("btn-outline", "btn-success")

      setTimeout(() => {
        button.innerHTML = originalText
        button.classList.remove("btn-success")
      }, 2000)
    } catch (_err) {
      this.sharingLinkTarget.select()
      this.sharingLinkTarget.setSelectionRange(0, 99999)
    }
  }
}
