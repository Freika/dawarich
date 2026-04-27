import { Controller } from "@hotwired/stimulus"
import Flash from "./flash_controller"

/**
 * Gap-fill controller: manages the workflow of selecting two points on the map,
 * previewing a routed path between them via BRouter, and confirming to insert
 * inferred points. Alternatives are fetched lazily when the user clicks the arrows.
 */
export default class extends Controller {
  static targets = [
    "panel",
    "modeSelect",
    "confirmButton",
    "startPointLabel",
    "endPointLabel",
    "status",
    "alternativesNav",
    "alternativeLabel",
    "form",
    "startPointInput",
    "endPointInput",
    "modeInput",
    "alternativeInput",
  ]

  static values = {
    previewUrl: String,
    active: { type: Boolean, default: false },
  }

  connect() {
    this.startPoint = null
    this.endPoint = null
    this.currentAlternative = 0
    this.cachedRoutes = {} // { index: coordinates }
    this._selectingSlot = null // null = auto, "start" or "end" = re-picking

    this._handlePointSelected = this.handlePointSelected.bind(this)
    this._handleStart = this.enter.bind(this)
    this._handleStop = this.exit.bind(this)
    this._handleModeChange = this.modeChanged.bind(this)
    document.addEventListener(
      "gapfill:point-selected",
      this._handlePointSelected,
    )
    document.addEventListener("gapfill:start", this._handleStart)
    document.addEventListener("gapfill:stop", this._handleStop)
    this.modeSelectTarget.addEventListener("change", this._handleModeChange)
  }

  disconnect() {
    document.removeEventListener(
      "gapfill:point-selected",
      this._handlePointSelected,
    )
    document.removeEventListener("gapfill:start", this._handleStart)
    document.removeEventListener("gapfill:stop", this._handleStop)
    this.modeSelectTarget.removeEventListener("change", this._handleModeChange)
    if (this.activeValue) {
      this.exit()
    }
  }

  /**
   * Toggle gap-fill panel visibility and selection mode.
   */
  enter() {
    const isVisible = !this.panelTarget.classList.contains("hidden")

    if (isVisible) {
      this.exit()
    } else {
      this.activeValue = true
      this.startPoint = null
      this.endPoint = null
      this.currentAlternative = 0
      this.cachedRoutes = {}
      this._selectingSlot = null
      this.panelTarget.classList.remove("hidden")
      this.confirmButtonTarget.disabled = true
      this.alternativesNavTarget.classList.add("inactive")
      this.startPointLabelTarget.textContent = "-"
      this.endPointLabelTarget.textContent = "-"
      this.statusTarget.textContent = "Select the start point"

      // Close replay if active
      document.dispatchEvent(new CustomEvent("replay:stop"))

      document.dispatchEvent(new CustomEvent("gapfill:enter"))
      Flash.show("notice", "Gap-fill mode: click the start point on the map")
    }
  }

  /**
   * Exit gap-fill mode and clean up.
   */
  exit() {
    this.activeValue = false
    this.startPoint = null
    this.endPoint = null
    this.currentAlternative = 0
    this.cachedRoutes = {}
    this._selectingSlot = null
    this.panelTarget.classList.add("hidden")

    document.dispatchEvent(new CustomEvent("gapfill:exit"))
    document.dispatchEvent(new CustomEvent("gapfill:clear-preview"))
  }

  /**
   * Handle a point being selected on the map.
   * Supports re-selection: if a specific slot is targeted via _selectingSlot,
   * or if both are set, replaces the end point.
   */
  handlePointSelected(event) {
    const { pointId, lon, lat, timestamp } = event.detail
    const point = { id: pointId, lon, lat, timestamp }
    const label = `#${pointId} (${lat.toFixed(4)}, ${lon.toFixed(4)})`

    // Determine which slot to fill
    let slot = this._selectingSlot
    if (!slot) {
      if (!this.startPoint) slot = "start"
      else if (!this.endPoint) slot = "end"
      else slot = "end" // both set - replace end point
    }

    if (slot === "start") {
      this.startPoint = point
      this.startPointLabelTarget.textContent = label
      this._dispatchMarker("A", lon, lat)

      if (!this.endPoint) {
        this.endPointLabelTarget.textContent = "-"
        this.statusTarget.textContent = "Select the end point"
        Flash.show("notice", "Start point selected. Now click the end point.")
      } else {
        this._onBothSelected()
      }
    } else {
      this.endPoint = point
      this.endPointLabelTarget.textContent = label
      this._dispatchMarker("B", lon, lat)
      this._onBothSelected()
    }

    this._selectingSlot = null
  }

  /**
   * Swap start and end points.
   */
  swap() {
    if (!this.startPoint && !this.endPoint) return

    const tmp = this.startPoint
    this.startPoint = this.endPoint
    this.endPoint = tmp

    this.startPointLabelTarget.textContent = this.startPoint
      ? `#${this.startPoint.id} (${this.startPoint.lat.toFixed(4)}, ${this.startPoint.lon.toFixed(4)})`
      : "-"
    this.endPointLabelTarget.textContent = this.endPoint
      ? `#${this.endPoint.id} (${this.endPoint.lat.toFixed(4)}, ${this.endPoint.lon.toFixed(4)})`
      : "-"

    if (this.startPoint)
      this._dispatchMarker("A", this.startPoint.lon, this.startPoint.lat)
    if (this.endPoint)
      this._dispatchMarker("B", this.endPoint.lon, this.endPoint.lat)

    if (this.startPoint && this.endPoint) {
      this._fetchPreview()
    }
  }

  /**
   * Re-pick the start point (A). Click the badge in the panel.
   */
  reselectStart() {
    this._selectingSlot = "start"
    this._invalidatePreview()
    this.startPointLabelTarget.textContent = "-"
    this.statusTarget.textContent = "Click a new start point"
  }

  /**
   * Re-pick the end point (B). Click the badge in the panel.
   */
  reselectEnd() {
    this._selectingSlot = "end"
    this._invalidatePreview()
    this.endPointLabelTarget.textContent = "-"
    this.statusTarget.textContent = "Click a new end point"
  }

  /**
   * Re-fetch route when transport mode changes.
   */
  modeChanged() {
    if (this.startPoint && this.endPoint) {
      this._fetchPreview()
    }
  }

  /**
   * Show previous alternative route (fetches lazily).
   */
  async prevAlternative() {
    const prev = this.currentAlternative - 1
    if (prev < 0) return
    await this._fetchAndShowRoute(prev)
  }

  /**
   * Show next alternative route (fetches lazily, max 3).
   */
  async nextAlternative() {
    const next = this.currentAlternative + 1
    if (next > 3) return
    await this._fetchAndShowRoute(next)
  }

  /**
   * Confirm and create inferred points from the currently selected alternative.
   * Submits a hidden form via Turbo to preserve standard Rails form handling.
   */
  confirm() {
    if (!this.startPoint || !this.endPoint) return

    this.confirmButtonTarget.disabled = true
    this.statusTarget.textContent = "Creating points..."

    this.startPointInputTarget.value = this.startPoint.id
    this.endPointInputTarget.value = this.endPoint.id
    this.modeInputTarget.value = this.modeSelectTarget.value
    this.alternativeInputTarget.value = this.currentAlternative

    this.formTarget.requestSubmit()
    this.exit()
  }

  // --- Private ---

  async _fetchAndShowRoute(index) {
    // Use cache if available
    if (this.cachedRoutes[index]) {
      this.currentAlternative = index
      this._drawRoute(this.cachedRoutes[index])
      return
    }

    this.statusTarget.textContent = `Loading ${this._routeName(index)}...`

    try {
      const csrfToken = document.querySelector(
        'meta[name="csrf-token"]',
      )?.content
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
        },
        body: JSON.stringify({
          start_point_id: this.startPoint.id,
          end_point_id: this.endPoint.id,
          mode: this.modeSelectTarget.value,
          alternative: index,
        }),
      })

      if (!response.ok) {
        if (index > 0) {
          // No more alternatives available
          Flash.show("notice", "No more alternative routes available")
          this.statusTarget.textContent = `${this._routeName(this.currentAlternative)} - ${this.cachedRoutes[this.currentAlternative].length} points`
        } else {
          const err = await response.json()
          Flash.show("error", err.error || "Routing failed")
          this.statusTarget.textContent = "Routing failed. Try again."
        }
        return
      }

      const { coordinates } = await response.json()
      this.cachedRoutes[index] = coordinates
      this.currentAlternative = index
      this._drawRoute(coordinates)
    } catch (e) {
      Flash.show("error", `Preview failed: ${e.message}`)
      this.statusTarget.textContent = "Error. Try again."
    }
  }

  _routeName(index) {
    return index === 0 ? "Original" : `Alt ${index}`
  }

  _drawRoute(coordinates) {
    document.dispatchEvent(
      new CustomEvent("gapfill:preview", {
        detail: { coordinates },
      }),
    )

    const name = this._routeName(this.currentAlternative)
    this.alternativeLabelTarget.textContent = name
    this.statusTarget.textContent = `${name} - ${coordinates.length} points. Confirm to insert.`
  }

  _onBothSelected() {
    this._invalidatePreview()
    this._fetchPreview()
  }

  async _fetchPreview() {
    this.cachedRoutes = {}
    this.currentAlternative = 0
    document.dispatchEvent(new CustomEvent("gapfill:clear-preview"))

    await this._fetchAndShowRoute(0)
    if (this.cachedRoutes[0]) {
      this.confirmButtonTarget.disabled = false
      this.alternativesNavTarget.classList.remove("inactive")
    }
  }

  _invalidatePreview() {
    this.cachedRoutes = {}
    this.currentAlternative = 0
    this.confirmButtonTarget.disabled = true
    this.alternativesNavTarget.classList.add("inactive")
    this.alternativeLabelTarget.textContent = "-"
    document.dispatchEvent(new CustomEvent("gapfill:clear-preview"))
  }

  _dispatchMarker(label, lon, lat) {
    document.dispatchEvent(
      new CustomEvent("gapfill:marker", {
        detail: { label, lon, lat },
      }),
    )
  }
}
