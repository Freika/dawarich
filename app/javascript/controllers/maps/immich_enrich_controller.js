import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import Flash from "../flash_controller"

export default class extends Controller {
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
  ]

  static values = { apiKey: String, toggleBtn: String, immichUrl: String }

  connect() {
    this.matches = []
    this.markers = []
    this.initDateDefaults()
    this.bindToggleButton()
  }

  disconnect() {
    this.removeMarkers()
    this.unbindToggleButton()
    this.hideThumbTooltip()
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
    }
  }

  initDateDefaults() {
    const mapController = this.findMapController()
    if (!mapController) return

    const startDate = mapController.startDateValue
    const endDate = mapController.endDateValue

    if (startDate && this.hasStartDateTarget) {
      this.startDateTarget.value = startDate.split("T")[0]
    }
    if (endDate && this.hasEndDateTarget) {
      this.endDateTarget.value = endDate.split("T")[0]
    }
  }

  async scan() {
    const startDate = this.startDateTarget.value
    const endDate = this.endDateTarget.value
    const tolerance = (parseInt(this.toleranceTarget.value, 10) || 30) * 60

    if (!startDate || !endDate) {
      Flash.show("error", "Please select a date range")
      return
    }

    this.showLoading("Scanning Immich photos...")
    this.removeMarkers()

    try {
      const response = await fetch(
        `/api/v1/immich/enrich/scan?api_key=${this.apiKeyValue}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            start_date: startDate,
            end_date: endDate,
            tolerance,
          }),
        },
      )

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
      Flash.show("error", "Failed to scan photos")
      this.showScanForm()
    }
  }

  renderResults(data) {
    this.resultsSummaryTarget.textContent = `${data.total_matched} of ${data.total_without_geodata} photos matched`

    this.matchListTarget.innerHTML = ""

    this.matches.forEach((match, index) => {
      const timeDelta = this.formatTimeDelta(match.time_delta_seconds)
      const badgeClass = this.confidenceBadgeClass(match.time_delta_seconds)

      const item = document.createElement("div")
      item.className =
        "flex items-start gap-2 p-2 rounded-lg bg-base-100 cursor-pointer hover:bg-base-300 transition-colors"
      item.dataset.index = index
      item.dataset.action = "click->maps--immich-enrich#focusMatch"

      const thumbUrl = `/api/v1/photos/${match.immich_asset_id}/thumbnail?source=immich&api_key=${this.apiKeyValue}`
      const immichPhotoUrl = `${this.immichUrlValue}/photos/${match.immich_asset_id}`

      const externalLinkSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/></svg>`

      item.innerHTML = `
        <input type="checkbox" class="checkbox checkbox-xs mt-1" checked
               data-index="${index}"
               data-action="change->maps--immich-enrich#updateSelection">
        <div class="flex-shrink-0 enrich-thumb-wrapper"
             data-thumb-url="${thumbUrl}"
             data-filename="${this.escapeHtml(match.filename)}">
          <img src="${thumbUrl}" alt="${this.escapeHtml(match.filename)}"
               class="w-10 h-10 rounded object-cover"
               loading="lazy"
               onerror="this.parentElement.style.display='none'">
        </div>
        <div class="flex-1 min-w-0">
          <div class="text-sm font-medium truncate">${this.escapeHtml(match.filename)}</div>
          <div class="text-xs text-base-content/60">
            ${this.formatDatetime(match.photo_timestamp)}
          </div>
          <div class="text-xs text-base-content/60">
            ${timeDelta} delta
            <span class="badge badge-xs ${badgeClass} ml-1">${match.match_method}</span>
          </div>
          <div class="text-xs text-base-content/50">
            ${match.latitude.toFixed(4)}°, ${match.longitude.toFixed(4)}°
          </div>
        </div>
        <a href="${immichPhotoUrl}" target="_blank" rel="noopener noreferrer"
           class="btn btn-ghost btn-xs flex-shrink-0 self-center opacity-50 hover:opacity-100"
           title="Open in Immich"
           onclick="event.stopPropagation()">
          ${externalLinkSvg}
        </a>
      `

      this.matchListTarget.appendChild(item)
    })

    this.bindThumbHovers()
    this.updateEnrichButton()
    this.showResults()
    this.addMarkers()
  }

  bindThumbHovers() {
    this.matchListTarget
      .querySelectorAll(".enrich-thumb-wrapper")
      .forEach((wrapper) => {
        wrapper.addEventListener("mouseenter", (e) =>
          this.showThumbTooltip(e, wrapper),
        )
        wrapper.addEventListener("mouseleave", () => this.hideThumbTooltip())
      })
  }

  showThumbTooltip(event, wrapper) {
    this.hideThumbTooltip()

    const url = wrapper.dataset.thumbUrl
    const name = wrapper.dataset.filename

    const tooltip = document.createElement("div")
    tooltip.id = "enrich-thumb-tooltip"
    tooltip.style.cssText = `
      position: fixed; z-index: 9999; pointer-events: none;
      padding: 4px; background: var(--fallback-b1, oklch(var(--b1)));
      border-radius: 8px; box-shadow: 0 8px 24px rgba(0,0,0,0.3);
      border: 1px solid var(--fallback-b3, oklch(var(--b3)));
    `
    tooltip.innerHTML = `
      <img src="${url}" alt="${name}"
           style="width: 200px; height: 200px; object-fit: cover; border-radius: 6px; display: block;">
      <div style="text-align: center; font-size: 11px; padding: 4px 0 2px; opacity: 0.7;
                  max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
        ${name}
      </div>
    `

    document.body.appendChild(tooltip)

    const rect = wrapper.getBoundingClientRect()
    const ttRect = tooltip.getBoundingClientRect()

    let top = rect.top - ttRect.height - 8
    if (top < 8) top = rect.bottom + 8

    let left = rect.left + rect.width / 2 - ttRect.width / 2
    left = Math.max(8, Math.min(left, window.innerWidth - ttRect.width - 8))

    tooltip.style.top = `${top}px`
    tooltip.style.left = `${left}px`
  }

  hideThumbTooltip() {
    const existing = document.getElementById("enrich-thumb-tooltip")
    if (existing) existing.remove()
  }

  focusMatch(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    const match = this.matches[index]
    if (!match) return

    const map = this.getMap()
    if (map) {
      map.flyTo({ center: [match.longitude, match.latitude], zoom: 15 })
    }

    // Highlight list item
    this.matchListTarget.querySelectorAll("[data-index]").forEach((el) => {
      el.classList.remove("ring-2", "ring-primary")
    })
    event.currentTarget.classList.add("ring-2", "ring-primary")
  }

  toggleSelectAll() {
    const checked = this.selectAllTarget.checked
    this.matchListTarget
      .querySelectorAll("input[type=checkbox]")
      .forEach((cb) => {
        cb.checked = checked
      })
    this.updateEnrichButton()
    this.updateAllMarkerStyles()
  }

  updateSelection(event) {
    const index = parseInt(event.target.dataset.index, 10)
    this.updateMarkerStyle(index, event.target.checked)
    this.updateEnrichButton()
  }

  updateEnrichButton() {
    const count = this.selectedCount()
    this.enrichButtonTarget.textContent = `Enrich ${count} photo${count !== 1 ? "s" : ""}`
    this.enrichButtonTarget.disabled = count === 0
  }

  selectedCount() {
    return this.matchListTarget.querySelectorAll("input[type=checkbox]:checked")
      .length
  }

  selectedMatches() {
    const selected = []
    this.matchListTarget
      .querySelectorAll("input[type=checkbox]:checked")
      .forEach((cb) => {
        const index = parseInt(cb.dataset.index, 10)
        const match = this.matches[index]
        if (match) {
          // Use marker position if it was dragged, otherwise use original
          const marker = this.markers[index]
          if (marker) {
            const lngLat = marker.getLngLat()
            selected.push({
              immich_asset_id: match.immich_asset_id,
              latitude: lngLat.lat,
              longitude: lngLat.lng,
            })
          } else {
            selected.push({
              immich_asset_id: match.immich_asset_id,
              latitude: match.latitude,
              longitude: match.longitude,
            })
          }
        }
      })
    return selected
  }

  async enrich() {
    const assets = this.selectedMatches()
    if (assets.length === 0) return

    this.showLoading(`Enriching ${assets.length} photos...`)

    try {
      const response = await fetch(
        `/api/v1/immich/enrich?api_key=${this.apiKeyValue}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ assets }),
        },
      )

      const data = await response.json()

      if (data.error) {
        Flash.show("error", data.error)
        this.showResults()
        return
      }

      const message =
        data.failed > 0
          ? `Enriched ${data.enriched} photos. ${data.failed} failed.`
          : `Successfully enriched ${data.enriched} photos!`

      Flash.show(data.failed > 0 ? "warning" : "notice", message)
      this.removeMarkers()
      this.showScanForm()
    } catch (error) {
      console.error("[Immich Enrich] Enrich failed:", error)
      Flash.show("error", "Failed to enrich photos")
      this.showResults()
    }
  }

  backToScan() {
    this.removeMarkers()
    this.showScanForm()
  }

  // Map marker management
  addMarkers() {
    const map = this.getMap()
    if (!map) return

    this.markerElements = []

    this.matches.forEach((match, index) => {
      const el = this.buildMarkerElement(match, index, true)

      el.addEventListener("click", (e) => {
        e.stopPropagation()
        const mapRef = this.getMap()
        if (mapRef) {
          mapRef.flyTo({
            center: [match.longitude, match.latitude],
            zoom: 15,
          })
        }
        this.matchListTarget
          .querySelectorAll("[data-index]")
          .forEach((item) => {
            item.classList.remove("ring-2", "ring-primary")
          })
        const listItem = this.matchListTarget.querySelector(
          `[data-index="${index}"]`,
        )
        if (listItem) {
          listItem.classList.add("ring-2", "ring-primary")
          listItem.scrollIntoView({ behavior: "smooth", block: "nearest" })
        }
      })

      const marker = new maplibregl.Marker({ element: el, draggable: true })
        .setLngLat([match.longitude, match.latitude])
        .addTo(map)

      marker.on("dragend", () => {
        const lngLat = marker.getLngLat()
        const listItem = this.matchListTarget.querySelector(
          `[data-index="${index}"]`,
        )
        if (listItem) {
          const coordEl = listItem.querySelector(".text-base-content\\/50")
          if (coordEl) {
            coordEl.textContent = `${lngLat.lat.toFixed(4)}°, ${lngLat.lng.toFixed(4)}°`
          }
        }
      })

      this.markers[index] = marker
      this.markerElements[index] = el
    })

    if (this.matches.length > 0) {
      const bounds = new maplibregl.LngLatBounds()
      for (const m of this.matches) {
        bounds.extend([m.longitude, m.latitude])
      }
      map.fitBounds(bounds, { padding: 50, maxZoom: 15 })
    }
  }

  buildMarkerElement(match, _index, selected) {
    const el = document.createElement("div")
    el.className = "immich-enrich-marker"
    this.applyMarkerStyle(el, match, selected, true)
    el.title = `${match.filename} (${this.formatTimeDelta(match.time_delta_seconds)} delta)`
    return el
  }

  applyMarkerStyle(el, match, selected, initial = false) {
    const color = selected
      ? this.confidenceColor(match.time_delta_seconds)
      : "#9ca3af"
    const icon = selected ? "📷✓" : "📷"

    if (initial) {
      // Only set cssText on first creation, before MapLibre adds transform
      el.style.cssText = `
        width: 32px; height: 32px; border-radius: 50%;
        background: ${color}; border: 2px solid white;
        box-shadow: 0 2px 6px rgba(0,0,0,0.3);
        cursor: grab; display: flex; align-items: center; justify-content: center;
        font-size: 12px; pointer-events: auto; z-index: 10;
      `
    } else {
      // Update only visual properties, preserve MapLibre's transform
      el.style.background = color
      el.style.border = selected ? "2px solid white" : "2px dashed #6b7280"
      el.style.opacity = selected ? "1" : "0.6"
    }
    el.textContent = icon
  }

  updateMarkerStyle(index, selected) {
    const el = this.markerElements?.[index]
    const match = this.matches[index]
    if (el && match) {
      this.applyMarkerStyle(el, match, selected)
    }
  }

  updateAllMarkerStyles() {
    this.matchListTarget
      .querySelectorAll("input[type=checkbox]")
      .forEach((cb) => {
        const index = parseInt(cb.dataset.index, 10)
        this.updateMarkerStyle(index, cb.checked)
      })
  }

  removeMarkers() {
    this.markers.forEach((marker) => {
      if (marker) marker.remove()
    })
    this.markers = []
    this.markerElements = []
  }

  // UI state management
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

  // Helpers
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

  formatDatetime(isoString) {
    const d = new Date(isoString)
    return d.toLocaleString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    })
  }

  formatTimeDelta(seconds) {
    if (seconds < 60) return `${seconds}s`
    const minutes = Math.round(seconds / 60)
    return `${minutes}m`
  }

  confidenceColor(timeDelta) {
    if (timeDelta < 300) return "#22c55e" // green: < 5 min
    if (timeDelta < 900) return "#eab308" // yellow: 5-15 min
    return "#f97316" // orange: > 15 min
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
