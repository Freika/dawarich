import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tooltip", "tooltipDate", "tooltipDistance"]
  static values = {
    unit: String
  }

  showTooltip(event) {
    const cell = event.currentTarget
    const date = cell.dataset.date
    const distance = parseFloat(cell.dataset.distance) || 0

    if (!date) return

    const formattedDate = this.formatDate(date)
    const formattedDistance = this.formatDistance(distance)

    this.tooltipDateTarget.textContent = formattedDate
    this.tooltipDistanceTarget.textContent = formattedDistance

    // Position tooltip
    const rect = cell.getBoundingClientRect()
    const containerRect = this.element.getBoundingClientRect()

    // Calculate position relative to the container
    let left = rect.left - containerRect.left + rect.width / 2
    let top = rect.top - containerRect.top - 8

    // Show tooltip to measure its size
    this.tooltipTarget.classList.remove("hidden")
    this.tooltipTarget.classList.add("flex")

    const tooltipRect = this.tooltipTarget.getBoundingClientRect()

    // Adjust horizontal position to keep tooltip within container
    left = Math.max(tooltipRect.width / 2 + 4, Math.min(left, containerRect.width - tooltipRect.width / 2 - 4))

    this.tooltipTarget.style.left = `${left}px`
    this.tooltipTarget.style.top = `${top}px`
    this.tooltipTarget.style.transform = "translate(-50%, -100%)"
  }

  hideTooltip() {
    this.tooltipTarget.classList.add("hidden")
    this.tooltipTarget.classList.remove("flex")
  }

  formatDate(dateStr) {
    const date = new Date(dateStr + "T00:00:00")
    const options = { weekday: "short", month: "short", day: "numeric", year: "numeric" }
    return date.toLocaleDateString("en-US", options)
  }

  formatDistance(distanceMeters) {
    if (distanceMeters === 0) {
      return "No activity"
    }

    const unit = this.unitValue || "km"

    if (unit === "mi") {
      const miles = distanceMeters / 1609.344
      if (miles < 1) {
        return `${(miles * 5280).toFixed(0)} ft`
      }
      return `${miles.toFixed(1)} mi`
    } else {
      const km = distanceMeters / 1000
      if (km < 1) {
        return `${distanceMeters.toFixed(0)} m`
      }
      return `${km.toFixed(1)} km`
    }
  }
}
