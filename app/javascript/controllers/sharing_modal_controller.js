import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["enableToggle", "expirationSettings", "sharingLink", "loading", "expirationSelect"]
  static values = { url: String }

  connect() {
    console.log("Sharing modal controller connected")
  }

  toggleSharing() {
    const isEnabled = this.enableToggleTarget.checked

    if (isEnabled) {
      this.expirationSettingsTarget.classList.remove("hidden")
      this.saveSettings() // Save immediately when enabling
    } else {
      this.expirationSettingsTarget.classList.add("hidden")
      this.sharingLinkTarget.value = ""
      this.saveSettings() // Save immediately when disabling
    }
  }

  expirationChanged() {
    // Save settings immediately when expiration changes
    if (this.enableToggleTarget.checked) {
      this.saveSettings()
    }
  }

  saveSettings() {
    // Show loading state
    this.showLoadingState()

    const formData = new FormData()
    formData.append('enabled', this.enableToggleTarget.checked ? '1' : '0')
    
    if (this.enableToggleTarget.checked && this.hasExpirationSelectTarget) {
      formData.append('expiration', this.expirationSelectTarget.value || '1h')
    } else if (this.enableToggleTarget.checked) {
      formData.append('expiration', '1h')
    }

    // Use the URL value from the controller
    const url = this.urlValue

    fetch(url, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'X-Requested-With': 'XMLHttpRequest'
      },
      body: formData
    })
    .then(response => response.json())
    .then(data => {
      this.hideLoadingState()
      
      if (data.success) {
        // Update sharing link if provided
        if (data.sharing_url) {
          this.sharingLinkTarget.value = data.sharing_url
        }
        
        // Show a subtle notification for auto-save
        this.showNotification("✓ Auto-saved", "success")
      } else {
        this.showNotification("Failed to save settings. Please try again.", "error")
      }
    })
    .catch(error => {
      console.error('Error:', error)
      this.hideLoadingState()
      this.showNotification("Failed to save settings. Please try again.", "error")
    })
  }

  showLoadingState() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("hidden")
    }
  }

  hideLoadingState() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.add("hidden")
    }
  }

  async copyLink() {
    try {
      await navigator.clipboard.writeText(this.sharingLinkTarget.value)

      // Show temporary success feedback
      const button = this.sharingLinkTarget.nextElementSibling
      const originalText = button.innerHTML
      button.innerHTML = "✅ Copied!"
      button.classList.add("btn-success")

      setTimeout(() => {
        button.innerHTML = originalText
        button.classList.remove("btn-success")
      }, 2000)

    } catch (err) {
      console.error("Failed to copy: ", err)

      // Fallback: select the text
      this.sharingLinkTarget.select()
      this.sharingLinkTarget.setSelectionRange(0, 99999) // For mobile devices
    }
  }

  showNotification(message, type) {
    // Create a simple toast notification
    const toast = document.createElement('div')
    toast.className = `toast toast-top toast-end z-50`
    toast.innerHTML = `
      <div class="alert alert-${type === 'success' ? 'success' : 'error'}">
        <span>${message}</span>
      </div>
    `

    document.body.appendChild(toast)

    // Remove after 3 seconds
    setTimeout(() => {
      toast.remove()
    }, 3000)
  }

}
