import { translate } from "i18n"
import Flash from "../../flash_controller"

const EXTERNAL_LINK_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/></svg>`

/**
 * Scan results: the match list, thumbnails, selection and the enrich request.
 * Mixed into ImmichEnrichController; `this` is the ImmichEnrichController.
 */
export const matchList = {
  renderResults(data) {
    if (this.matches.length === 0) {
      this.resultsSummaryTarget.innerHTML = `
        <div class="text-center py-3">
          <div class="text-base-content/40 text-2xl mb-1">📷</div>
          <div class="text-sm font-medium">${translate("immich.photos_without_gps", { count: data.total_without_geodata })}</div>
          <div class="text-xs text-base-content/50">${translate("immich.no_matches")}</div>
        </div>
      `
      this.matchListTarget.innerHTML = ""
      this.updateEnrichButton()
      this.showResults()
      return
    }

    this.resultsSummaryTarget.textContent = translate(
      "immich.matched_summary",
      {
        matched: data.total_matched,
        total: data.total_without_geodata,
      },
    )
    this.matchListTarget.innerHTML = ""

    for (const [index, match] of this.matches.entries()) {
      this.matchListTarget.appendChild(this.buildMatchItem(match, index))
    }

    this.bindThumbHovers()
    this.updateEnrichButton()
    this.showResults()
    this.addMarkers()
  },

  buildMatchItem(match, index) {
    const timeDelta = this.formatTimeDelta(match.time_delta_seconds)
    const badgeClass = this.confidenceBadgeClass(match.time_delta_seconds)
    const thumbUrl = this.thumbnailUrl(match.immich_asset_id)
    const immichPhotoUrl = `${this.immichUrlValue}/photos/${match.immich_asset_id}`

    const item = document.createElement("div")
    item.className =
      "flex items-center gap-2 p-2 rounded-lg bg-base-100 cursor-pointer hover:bg-base-300/50 transition-all border border-transparent hover:border-base-300"
    item.dataset.index = index
    item.dataset.action = "click->maps--immich-enrich#focusMatch"

    item.innerHTML = `
      <input type="checkbox" class="checkbox checkbox-xs checkbox-primary" checked
             data-index="${index}"
             data-action="change->maps--immich-enrich#updateSelection"
             onclick="event.stopPropagation()">
      <div class="flex-shrink-0 enrich-thumb-wrapper"
           data-thumb-url="${thumbUrl}"
           data-filename="${this.escapeHtml(match.filename)}">
        <img src="${thumbUrl}" alt=""
             class="w-10 h-10 rounded-md object-cover ring-1 ring-base-300"
             loading="lazy"
             onerror="this.parentElement.style.display='none'">
      </div>
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium truncate leading-tight">${this.escapeHtml(match.filename)}</div>
        <div class="text-xs text-base-content/50 leading-tight mt-0.5">
          ${this.formatDatetime(match.photo_timestamp)}
          <span class="mx-0.5">&middot;</span>
          <span class="badge badge-xs ${badgeClass}">${match.match_method}</span>
          <span class="mx-0.5">&middot;</span>
          ${timeDelta}
        </div>
        <div class="text-xs text-base-content/40 leading-tight font-mono" data-coord>
          ${match.latitude.toFixed(4)}, ${match.longitude.toFixed(4)}
        </div>
      </div>
      <a href="${immichPhotoUrl}" target="_blank" rel="noopener noreferrer"
         class="btn btn-ghost btn-xs btn-square flex-shrink-0 opacity-40 hover:opacity-100"
         title="${translate("immich.open_in_immich")}"
         onclick="event.stopPropagation()">
        ${EXTERNAL_LINK_SVG}
      </a>
    `
    return item
  },

  // --- Thumbnail tooltip ---

  bindThumbHovers() {
    this.matchListTarget
      .querySelectorAll(".enrich-thumb-wrapper")
      .forEach((wrapper) => {
        wrapper.addEventListener("mouseenter", (e) =>
          this.showThumbTooltip(e, wrapper),
        )
        wrapper.addEventListener("mouseleave", () => this.hideThumbTooltip())
      })
  },

  showThumbTooltip(_event, wrapper) {
    this.hideThumbTooltip()

    const url = wrapper.dataset.thumbUrl
    const name = wrapper.dataset.filename

    const tooltip = document.createElement("div")
    tooltip.id = "enrich-thumb-tooltip"
    tooltip.style.cssText = `
      position: fixed; z-index: 9999; pointer-events: none;
      padding: 4px; background: var(--fallback-b1, oklch(var(--b1)));
      border-radius: 12px; box-shadow: 0 12px 32px rgba(0,0,0,0.25);
      border: 1px solid var(--fallback-b3, oklch(var(--b3)));
    `
    tooltip.innerHTML = `
      <img src="${url}" alt="${name}"
           style="width: 220px; height: 220px; object-fit: cover; border-radius: 8px; display: block;"
           onerror="this.parentElement.remove()">
      <div style="text-align: center; font-size: 11px; padding: 4px 0 2px; opacity: 0.6;
                  max-width: 220px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
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
  },

  hideThumbTooltip() {
    const existing = document.getElementById("enrich-thumb-tooltip")
    if (existing) existing.remove()
  },

  // --- List interaction ---

  focusMatch(event) {
    const item = event.currentTarget
    const index = parseInt(item.dataset.index, 10)
    const match = this.matches[index]
    if (!match) return

    const marker = this.markers[index]
    const lngLat = marker ? marker.getLngLat() : null
    const lng = lngLat ? lngLat.lng : match.longitude
    const lat = lngLat ? lngLat.lat : match.latitude

    const map = this.getMap()
    if (map) {
      map.flyTo({ center: [lng, lat], zoom: 15 })
    }

    this.matchListTarget.querySelectorAll("[data-index]").forEach((el) => {
      el.classList.remove("ring-2", "ring-primary")
    })
    item.classList.add("ring-2", "ring-primary")
  },

  toggleSelectAll() {
    const checked = this.selectAllTarget.checked
    this.matchListTarget
      .querySelectorAll("input[type=checkbox]")
      .forEach((cb) => {
        cb.checked = checked
      })
    this.updateEnrichButton()
    this.updateAllMarkerStyles()
  },

  updateSelection(event) {
    const index = parseInt(event.target.dataset.index, 10)
    this.updateMarkerStyle(index, event.target.checked)
    this.updateEnrichButton()
  },

  updateEnrichButton() {
    const count = this.selectedCount()
    this.enrichButtonTarget.textContent = translate("immich.enrich_photos", {
      count,
    })
    this.enrichButtonTarget.disabled = count === 0
  },

  selectedCount() {
    return this.matchListTarget.querySelectorAll("input[type=checkbox]:checked")
      .length
  },

  selectedMatches() {
    const selected = []
    this.matchListTarget
      .querySelectorAll("input[type=checkbox]:checked")
      .forEach((cb) => {
        const index = parseInt(cb.dataset.index, 10)
        const match = this.matches[index]
        if (!match) return

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
      })
    return selected
  },

  // --- Enrich ---

  async enrich() {
    const assets = this.selectedMatches()
    if (assets.length === 0) return

    const confirmed = window.confirm(
      translate("immich.confirm_enrich", { count: assets.length }),
    )
    if (!confirmed) return

    this.showLoading(translate("immich.enriching", { count: assets.length }))

    try {
      const response = await fetch("/api/v1/immich/enrich", {
        method: "POST",
        headers: this.apiHeaders(),
        body: JSON.stringify({ assets }),
      })

      const data = await response.json()

      if (data.error) {
        Flash.show("error", data.error)
        this.showResults()
        return
      }

      const message =
        data.pending > 0
          ? translate("immich.pending_enrichment", {
              count: data.pending,
              failed: data.failed,
            })
          : data.failed > 0
            ? translate("immich.partially_enriched", {
                enriched: data.enriched,
                failed: data.failed,
              })
            : translate("immich.enriched", { count: data.enriched })

      Flash.show(data.failed > 0 ? "warning" : "notice", message)
      this.removeMarkers()
      this.showScanForm()
    } catch (error) {
      console.error("[Immich Enrich] Enrich failed:", error)
      Flash.show("error", translate("messages.failed_to_enrich_photos"))
      this.showResults()
    }
  },

  backToScan() {
    this.removeMarkers()
    this.showScanForm()
  },
}
