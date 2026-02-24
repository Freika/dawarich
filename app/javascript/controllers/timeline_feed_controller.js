import { Controller } from "@hotwired/stimulus"

/**
 * Timeline Feed Controller
 * Handles accordion single-expand, map bounds coordination,
 * inline track info toggle via Turbo Frames, and entry hover highlighting.
 */
export default class extends Controller {
  static targets = ["dayDetails", "trackInfoFrame"]

  /**
   * Called when a <details> element is toggled.
   * Implements single-expand: close other open days and
   * dispatch bounds event for the map controller.
   */
  dayToggled(event) {
    const toggled = event.currentTarget

    if (!toggled.open) {
      // Check if all days are now closed
      const anyOpen = this.dayDetailsTargets.some((d) => d.open)
      if (!anyOpen) {
        document.dispatchEvent(new CustomEvent("timeline-feed:day-collapsed"))
      }
      return
    }

    // Close other open days (single-expand)
    for (const details of this.dayDetailsTargets) {
      if (details !== toggled && details.open) {
        details.open = false
      }
    }

    // Dispatch bounds + day date for map controller
    const boundsJson = toggled.dataset.bounds
    const day = toggled.dataset.day // e.g. "2025-01-15"

    try {
      const bounds =
        boundsJson && boundsJson !== "null" ? JSON.parse(boundsJson) : null
      document.dispatchEvent(
        new CustomEvent("timeline-feed:day-expanded", {
          detail: { bounds, day },
        }),
      )
    } catch {
      // Ignore malformed data
    }
  }

  /**
   * Toggle inline track info for a journey entry.
   * On first click, sets the Turbo Frame src to trigger lazy load.
   */
  toggleTrackInfo(event) {
    const target = event.currentTarget
    const frameId = target.dataset.frameId
    const trackId = target.dataset.trackId
    const frame = document.getElementById(frameId)

    if (!frame) return

    const isHidden = frame.classList.contains("hidden")

    if (isHidden) {
      // Show the frame
      frame.classList.remove("hidden")

      // Set src on first click to trigger Turbo Frame lazy load
      if (!frame.getAttribute("src")) {
        frame.src = `/map/timeline_feeds/${trackId}/track_info`
      }

      // Rotate chevron
      const chevron = target.querySelector(".track-info-chevron")
      if (chevron) chevron.style.transform = "rotate(180deg)"

      // Dispatch click event for the map controller
      const connector = target.closest(".timeline-journey-connector")
      if (connector) {
        const { startedAt, endedAt } = connector.dataset
        document.dispatchEvent(
          new CustomEvent("timeline-feed:entry-click", {
            detail: { trackId, startedAt, endedAt },
          }),
        )
      }
    } else {
      // Hide the frame
      frame.classList.add("hidden")

      // Reset chevron
      const chevron = target.querySelector(".track-info-chevron")
      if (chevron) chevron.style.transform = ""

      // Dispatch deselect event for the map controller
      document.dispatchEvent(new CustomEvent("timeline-feed:entry-deselect"))
    }
  }

  /**
   * Dispatch hover event for a timeline entry (visit or journey).
   * The map controller listens for this to highlight matching features.
   */
  entryHover(event) {
    const el = event.currentTarget
    const { entryType, startedAt, endedAt, trackId } = el.dataset
    if (!startedAt || !endedAt) return

    document.dispatchEvent(
      new CustomEvent("timeline-feed:entry-hover", {
        detail: { entryType, startedAt, endedAt, trackId },
      }),
    )
  }

  /**
   * Clear hover highlight when mouse leaves a timeline entry.
   */
  entryUnhover() {
    document.dispatchEvent(new CustomEvent("timeline-feed:entry-unhover"))
  }
}
