import { Controller } from "@hotwired/stimulus"

// Asks the server whether the period the map just loaded is the user's first
// look at their imported points, and if so sends first_map_data_viewed to
// Rybbit from this browser session. Rendered only until that view is recorded.
export default class extends Controller {
  static values = { url: String }

  // A period that loads while a request is in flight waits as pendingPeriod;
  // only the latest one is checked.
  async check(event) {
    this.pendingPeriod = event.detail
    if (this.checking) return
    this.checking = true

    while (this.pendingPeriod) {
      const detail = this.pendingPeriod
      this.pendingPeriod = null
      const period = `${detail.startDate}/${detail.endDate}`
      if (period !== this.checkedPeriod) await this.checkPeriod(detail, period)
    }
    this.checking = false
  }

  async checkPeriod({ startDate, endDate }, period) {
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token":
            document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
        body: JSON.stringify({ start_at: startDate, end_at: endDate }),
      })
      if (!response.ok) return

      const { status } = await response.json()
      this.checkedPeriod = period
      if (status === "recorded") this.sendEvent()
      if (status !== "no_imported_data") {
        this.pendingPeriod = null
        this.element.remove()
      }
    } catch (error) {
      console.warn("[FirstMapView] Check failed:", error)
    }
  }

  // Hands the event to analytics-event, which waits for the Rybbit script.
  sendEvent() {
    const signal = document.createElement("div")
    signal.hidden = true
    signal.dataset.controller = "analytics-event"
    signal.dataset.analyticsEventNameValue = "first_map_data_viewed"
    document.body.appendChild(signal)
  }
}
