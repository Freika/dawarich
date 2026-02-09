import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    userTimezone: String,
    updatePath: String,
  }

  connect() {
    // Only detect and save if user hasn't set a timezone yet
    if (!this.userTimezoneValue) {
      this.detectAndSaveTimezone()
    }
  }

  detectAndSaveTimezone() {
    try {
      const browserTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (browserTimezone && this.updatePathValue) {
        this.saveTimezone(browserTimezone)
      }
    } catch (error) {
      console.error("Failed to detect timezone:", error)
    }
  }

  saveTimezone(timezone) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this.updatePathValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrfToken,
      },
      body: JSON.stringify({ timezone: timezone }),
    }).catch((error) => {
      console.error("Failed to save timezone:", error)
    })
  }
}
