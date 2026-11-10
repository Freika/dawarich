import { Controller } from "@hotwired/stimulus"
import { formatDateTime, translate } from "i18n"
import Flash from "../flash_controller"
import { matchList } from "./immich_enrich/match_list"
import { matchMarkers } from "./immich_enrich/match_markers"

const SCAN_DEBOUNCE_MS = 2000

export default class ImmichEnrichController extends Controller {
  static targets = [
    "scanForm",
    "loading",
    "loadingText",
    "results",
    "resultsSummary",
    "matchList",
    "enrichButton",
    "selectAll",
    "startDate",
    "endDate",
    "tolerance",
    "scanButton",
  ]

  static values = { apiKey: String, toggleBtn: String, immichUrl: String }

  connect() {
    this.matches = []
    this.markers = []
    this.markerElements = []
    this.scanning = false
    this.rememberShownDates()
    this.followMapDates()
    this.bindToggleButton()
    this.boundFollowMapDates = () => queueMicrotask(() => this.followMapDates())
    document.addEventListener(
      "timeline-feed:date-navigated",
      this.boundFollowMapDates,
    )
  }

  disconnect() {
    this.removeMarkers()
    this.unbindToggleButton()
    this.hideThumbTooltip()
    document.removeEventListener(
      "timeline-feed:date-navigated",
      this.boundFollowMapDates,
    )
  }

  bindToggleButton() {
    if (!this.toggleBtnValue) return
    this.toggleButtonEl = document.getElementById(this.toggleBtnValue)
    if (this.toggleButtonEl) {
      this.boundToggle = () => this.toggle()
      this.toggleButtonEl.addEventListener("click", this.boundToggle)
    }
  }

  unbindToggleButton() {
    if (this.toggleButtonEl && this.boundToggle) {
      this.toggleButtonEl.removeEventListener("click", this.boundToggle)
    }
  }

  toggle() {
    this.element.classList.toggle("hidden")
    if (this.element.classList.contains("hidden")) {
      this.removeMarkers()
    } else {
      this.followMapDates()
    }
  }

  followMapDates() {
    const mapController = this.findMapController()
    if (!mapController || this.datesEditedByUser()) return

    const range = mapController.defaultDateRange
    const [start, end] = this.mapShowsPageLoadRange(mapController)
      ? [range.startDate, range.endDate]
      : [mapController.startDateValue, mapController.endDateValue].map(
          (value) => value.split("T")[0],
        )
    this.startDateTarget.value = start
    this.endDateTarget.value = end
    this.rememberShownDates()
  }

  mapShowsPageLoadRange(mapController) {
    const range = mapController.defaultDateRange
    return (
      range?.startValue === mapController.startDateValue &&
      range?.endValue === mapController.endDateValue
    )
  }

  datesEditedByUser() {
    const [start, end] = this.shownDates
    return (
      this.startDateTarget.value !== start || this.endDateTarget.value !== end
    )
  }

  rememberShownDates() {
    this.shownDates = [this.startDateTarget.value, this.endDateTarget.value]
  }

  // --- API helpers ---

  apiHeaders() {
    return {
      "Content-Type": "application/json",
      Authorization: `Bearer ${this.apiKeyValue}`,
    }
  }

  // --- Scan ---

  async scan() {
    if (this.scanning) return

    const startDate = this.startDateTarget.value
    const endDate = this.endDateTarget.value
    const tolerance = (parseInt(this.toleranceTarget.value, 10) || 30) * 60

    if (!startDate || !endDate) {
      Flash.show("error", translate("messages.please_select_a_date_range"))
      return
    }

    // Sync the map's date range and reload map data
    this.syncMapDateRange(startDate, endDate)

    this.scanning = true
    if (this.hasScanButtonTarget) this.scanButtonTarget.disabled = true
    this.showLoading(translate("immich.scanning"))
    this.removeMarkers()

    try {
      const response = await fetch("/api/v1/immich/enrich/scan", {
        method: "POST",
        headers: this.apiHeaders(),
        body: JSON.stringify({
          start_date: startDate,
          end_date: endDate,
          tolerance,
        }),
      })

      const data = await response.json()

      if (data.error) {
        Flash.show("error", data.error)
        this.showScanForm()
        return
      }

      this.matches = data.matches || []
      this.renderResults(data)
    } catch (error) {
      console.error("[Immich Enrich] Scan failed:", error)
      Flash.show("error", translate("messages.failed_to_scan_photos"))
      this.showScanForm()
    } finally {
      setTimeout(() => {
        this.scanning = false
        if (this.hasScanButtonTarget) this.scanButtonTarget.disabled = false
      }, SCAN_DEBOUNCE_MS)
    }
  }

  syncMapDateRange(startDate, endDate) {
    const startIso = `${startDate}T00:00`
    const endIso = `${endDate}T23:59`

    const mapController = this.findMapController()
    if (mapController) {
      void mapController.setDateRange(startIso, endIso)
      this.rememberShownDates()
    }

    // Update the date navigation inputs
    const startInput = document.querySelector("input[name='start_at']")
    const endInput = document.querySelector("input[name='end_at']")
    if (startInput) startInput.value = startIso
    if (endInput) endInput.value = endIso

    // Update URL without reload
    const url = new URL(window.location.href)
    url.searchParams.set("start_at", startIso)
    url.searchParams.set("end_at", endIso)
    window.history.replaceState({}, "", url.toString())
  }

  // --- UI state ---
  showLoading(text) {
    this.scanFormTarget.classList.add("hidden")
    this.resultsTarget.classList.add("hidden")
    this.loadingTarget.classList.remove("hidden")
    this.loadingTextTarget.textContent = text
  }

  showScanForm() {
    this.loadingTarget.classList.add("hidden")
    this.resultsTarget.classList.add("hidden")
    this.scanFormTarget.classList.remove("hidden")
  }

  showResults() {
    this.loadingTarget.classList.add("hidden")
    this.scanFormTarget.classList.add("hidden")
    this.resultsTarget.classList.remove("hidden")
  }

  // --- Helpers ---

  findMapController() {
    const mapElement = document.querySelector(
      "[data-controller*='maps--maplibre']",
    )
    if (!mapElement) return null
    return this.application.getControllerForElementAndIdentifier(
      mapElement,
      "maps--maplibre",
    )
  }

  getMap() {
    const controller = this.findMapController()
    return controller?.map || null
  }

  thumbnailUrl(assetId) {
    return `/api/v1/photos/${assetId}/thumbnail?source=immich&api_key=${this.apiKeyValue}`
  }

  formatDatetime(isoString) {
    return formatDateTime(isoString)
  }

  formatTimeDelta(seconds) {
    if (seconds < 60)
      return translate("immich.seconds_short", { count: seconds })
    const minutes = Math.round(seconds / 60)
    return translate("immich.minutes_short", { count: minutes })
  }

  confidenceColor(timeDelta) {
    if (timeDelta < 300) return "#22c55e"
    if (timeDelta < 900) return "#eab308"
    return "#f97316"
  }

  confidenceBadgeClass(timeDelta) {
    if (timeDelta < 300) return "badge-success"
    if (timeDelta < 900) return "badge-warning"
    return "badge-error"
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}

Object.assign(ImmichEnrichController.prototype, matchList, matchMarkers)
