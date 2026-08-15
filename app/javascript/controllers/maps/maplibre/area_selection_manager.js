import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { VisitCard } from "maps_maplibre/components/visit_card"
import { SelectedPointsLayer } from "maps_maplibre/layers/selected_points_layer"
import { SelectionLayer } from "maps_maplibre/layers/selection_layer"
import { pointsToGeoJSON } from "maps_maplibre/utils/geojson_transformers"

/**
 * Manages area selection and bulk operations for Maps V2
 * Handles selection mode, visit cards, and bulk actions (merge, confirm, delete)
 */
export class AreaSelectionManager {
  constructor(controller) {
    this.controller = controller
    this.map = controller.map
    this.api = controller.api
    this.selectionLayer = null
    this.selectedPointsLayer = null
    this.selectedVisits = []
    this.selectedVisitIds = new Set()
    this.selectedAnomalyIds = []
  }

  /**
   * Start area selection mode
   */
  async startSelectArea() {
    // Initialize selection layer if not exists
    if (!this.selectionLayer) {
      this.selectionLayer = new SelectionLayer(this.map, {
        visible: true,
        onSelectionComplete: this.handleAreaSelected.bind(this),
      })

      this.selectionLayer.add({
        type: "FeatureCollection",
        features: [],
      })
    }

    // Initialize selected points layer if not exists
    if (!this.selectedPointsLayer) {
      this.selectedPointsLayer = new SelectedPointsLayer(this.map, {
        visible: true,
      })

      this.selectedPointsLayer.add({
        type: "FeatureCollection",
        features: [],
      })
    }

    // Enable selection mode
    this.selectionLayer.enableSelectionMode()

    // Update UI - replace Select Area button with Cancel Selection button
    if (this.controller.hasSelectAreaButtonTarget) {
      this.controller.selectAreaButtonTarget.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-5 h-5">
          <line x1="18" y1="6" x2="6" y2="18"></line>
          <line x1="6" y1="6" x2="18" y2="18"></line>
        </svg>
        Cancel Selection
      `
      this.controller.selectAreaButtonTarget.dataset.action =
        "click->maps--maplibre#cancelAreaSelection"
    }

    Toast.info(
      translate("messages.draw_a_rectangle_on_the_map_to_select_points"),
    )
  }

  /**
   * Handle area selection completion
   */
  async handleAreaSelected(bounds) {
    try {
      Toast.info(translate("messages.fetching_data_in_selected_area"))

      const [points, visits] = await Promise.all([
        this.api.fetchPointsInArea({
          start_at: this.controller.startDateValue,
          end_at: this.controller.endDateValue,
          min_longitude: bounds.minLng,
          max_longitude: bounds.maxLng,
          min_latitude: bounds.minLat,
          max_latitude: bounds.maxLat,
        }),
        this.api.fetchVisitsInArea({
          start_at: this.controller.startDateValue,
          end_at: this.controller.endDateValue,
          sw_lat: bounds.minLat,
          sw_lng: bounds.minLng,
          ne_lat: bounds.maxLat,
          ne_lng: bounds.maxLng,
        }),
      ])

      console.log(
        "[Maps V2] Found",
        points.length,
        "points and",
        visits.length,
        "visits in area",
      )

      if (points.length === 0 && visits.length === 0) {
        Toast.info(translate("messages.no_data_found_in_selected_area"))
        this.cancelAreaSelection()
        return
      }

      // Convert points to GeoJSON and display
      if (points.length > 0) {
        const geojson = pointsToGeoJSON(points)
        this.selectedPointsLayer.updateSelectedPoints(geojson)
        this.selectedPointsLayer.show()
      }

      // Display visits in side panel and on map
      if (visits.length > 0) {
        this.displaySelectedVisits(visits)
      }

      // Update UI - show action buttons
      if (this.controller.hasSelectionActionsTarget) {
        this.controller.selectionActionsTarget.classList.remove("hidden")
      }

      // Update delete button text with count
      if (this.controller.hasDeleteButtonTextTarget) {
        this.controller.deleteButtonTextTarget.textContent = translate(
          "selection.delete_points",
          { count: points.length },
        )
      }

      // Track anomaly point IDs separately so the user can opt to delete
      // only the noisy points (returned by fetchPointsInArea?include_anomalies=true).
      this.selectedAnomalyIds = points
        .filter((p) => p.anomaly === true)
        .map((p) => p.id)
      if (this.controller.hasDeleteAnomaliesButtonTarget) {
        const btn = this.controller.deleteAnomaliesButtonTarget
        const anomalyCount = this.selectedAnomalyIds.length
        if (anomalyCount > 0) {
          btn.classList.remove("hidden")
          if (this.controller.hasDeleteAnomaliesButtonTextTarget) {
            this.controller.deleteAnomaliesButtonTextTarget.textContent =
              translate("selection.delete_anomaly_points", {
                count: anomalyCount,
              })
          }
        } else {
          btn.classList.add("hidden")
        }
      }

      // Disable selection mode
      this.selectionLayer.disableSelectionMode()

      const messages = []
      if (points.length > 0)
        messages.push(translate("selection.points", { count: points.length }))
      if (visits.length > 0)
        messages.push(translate("selection.visits", { count: visits.length }))

      Toast.success(
        translate("selection.selected", {
          items: messages.join(` ${translate("common.and")} `),
        }),
      )
    } catch (error) {
      console.error("[Maps V2] Failed to fetch data in area:", error)
      Toast.error(translate("messages.failed_to_fetch_data_in_selected_area"))
      this.cancelAreaSelection()
    }
  }

  /**
   * Display selected visits in side panel
   */
  displaySelectedVisits(visits) {
    if (!this.controller.hasSelectedVisitsContainerTarget) return

    this.selectedVisits = visits
    this.selectedVisitIds = new Set()

    const cardsHTML = visits
      .map((visit) => VisitCard.create(visit, { isSelected: false }))
      .join("")

    this.controller.selectedVisitsContainerTarget.innerHTML = `
      <div class="selected-visits-list">
        <div class="flex items-center gap-2 mb-3 pb-2 border-b border-base-300">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <h3 class="text-sm font-bold">${translate("selection.visits_in_area", { count: visits.length })}</h3>
        </div>
        ${cardsHTML}
      </div>
    `

    this.controller.selectedVisitsContainerTarget.classList.remove("hidden")
    this.attachVisitCardListeners()

    requestAnimationFrame(() => {
      this.updateBulkActions()
    })
  }

  /**
   * Attach event listeners to visit cards
   */
  attachVisitCardListeners() {
    this.controller.element
      .querySelectorAll("[data-visit-select]")
      .forEach((checkbox) => {
        checkbox.addEventListener("change", (e) => {
          const visitId = parseInt(e.target.dataset.visitSelect, 10)
          if (e.target.checked) {
            this.selectedVisitIds.add(visitId)
          } else {
            this.selectedVisitIds.delete(visitId)
          }
          this.updateBulkActions()
        })
      })

    this.controller.element
      .querySelectorAll("[data-visit-confirm]")
      .forEach((btn) => {
        btn.addEventListener("click", async (e) => {
          const visitId = parseInt(e.currentTarget.dataset.visitConfirm, 10)
          await this.confirmVisit(visitId)
        })
      })

    this.controller.element
      .querySelectorAll("[data-visit-delete]")
      .forEach((btn) => {
        btn.addEventListener("click", async (e) => {
          const visitId = parseInt(e.currentTarget.dataset.visitDelete, 10)
          await this.deleteVisit(visitId)
        })
      })
  }

  /**
   * Update bulk action buttons visibility and attach listeners
   */
  updateBulkActions() {
    const selectedCount = this.selectedVisitIds.size

    const existingBulkActions = this.controller.element.querySelectorAll(
      ".bulk-actions-inline",
    )
    existingBulkActions.forEach((el) => {
      el.remove()
    })

    if (selectedCount >= 2) {
      const selectedVisitCards = Array.from(
        this.controller.element.querySelectorAll(".visit-card"),
      ).filter((card) => {
        const visitId = parseInt(card.dataset.visitId, 10)
        return this.selectedVisitIds.has(visitId)
      })

      if (selectedVisitCards.length > 0) {
        const lastSelectedCard =
          selectedVisitCards[selectedVisitCards.length - 1]

        const bulkActionsDiv = document.createElement("div")
        bulkActionsDiv.className = "bulk-actions-inline mb-2"
        bulkActionsDiv.innerHTML = `
          <div class="bg-primary/10 border-2 border-primary border-dashed rounded-lg p-3">
            <div class="text-xs font-semibold mb-2 text-primary flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>${translate("visits.selected", { count: selectedCount })}</span>
            </div>
            <div class="grid grid-cols-3 gap-1.5">
              <button class="btn btn-xs btn-outline normal-case" data-bulk-merge>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
                </svg>
                ${translate("visits.merge")}
              </button>
              <button class="btn btn-xs btn-primary normal-case" data-bulk-confirm>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                ${translate("common.confirm")}
              </button>
              <button class="btn btn-xs btn-outline btn-error normal-case" data-bulk-delete>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
                ${translate("common.delete")}
              </button>
            </div>
          </div>
        `

        lastSelectedCard.insertAdjacentElement("afterend", bulkActionsDiv)

        const mergeBtn = bulkActionsDiv.querySelector("[data-bulk-merge]")
        const confirmBtn = bulkActionsDiv.querySelector("[data-bulk-confirm]")
        const deleteBtn = bulkActionsDiv.querySelector("[data-bulk-delete]")

        if (mergeBtn)
          mergeBtn.addEventListener("click", () => this.bulkMergeVisits())
        if (confirmBtn)
          confirmBtn.addEventListener("click", () => this.bulkConfirmVisits())
        if (deleteBtn)
          deleteBtn.addEventListener("click", () => this.bulkDeleteVisits())
      }
    }
  }

  /**
   * Confirm a single visit
   */
  async confirmVisit(visitId) {
    try {
      await this.api.updateVisitStatus(visitId, "confirmed")
      Toast.success(translate("messages.visit_confirmed"))
      await this.refreshSelectedVisits()
    } catch (error) {
      console.error("[Maps V2] Failed to confirm visit:", error)
      Toast.error(translate("messages.failed_to_confirm_visit"))
    }
  }

  /**
   * Delete a single visit
   */
  async deleteVisit(visitId) {
    if (!window.confirm(translate("visits.confirm_delete_keep_points"))) {
      return
    }
    try {
      await this.api.deleteVisit(visitId)
      Toast.success(translate("messages.visit_deleted"))
      await this.refreshSelectedVisits()
    } catch (_error) {
      Toast.error(translate("messages.failed_to_delete_visit"))
    }
  }

  /**
   * Bulk merge selected visits
   */
  async bulkMergeVisits() {
    const visitIds = Array.from(this.selectedVisitIds)

    if (visitIds.length < 2) {
      Toast.error(translate("messages.select_at_least_2_visits_to_merge"))
      return
    }

    if (
      !confirm(translate("visits.confirm_merge", { count: visitIds.length }))
    ) {
      return
    }

    try {
      Toast.info(translate("messages.merging_visits"))
      const mergedVisit = await this.api.mergeVisits(visitIds)
      Toast.success(translate("messages.visits_merged_successfully"))

      this.selectedVisitIds.clear()
      this.replaceVisitsWithMerged(visitIds, mergedVisit)
      this.updateBulkActions()
    } catch (_error) {
      Toast.error(translate("messages.failed_to_merge_visits"))
    }
  }

  /**
   * Bulk confirm selected visits
   */
  async bulkConfirmVisits() {
    const visitIds = Array.from(this.selectedVisitIds)

    try {
      Toast.info(translate("messages.confirming_visits"))
      await this.api.bulkUpdateVisits(visitIds, "confirmed")
      Toast.success(
        translate("visits.confirmed_count", { count: visitIds.length }),
      )

      this.selectedVisitIds.clear()
      await this.refreshSelectedVisits()
    } catch (_error) {
      Toast.error(translate("messages.failed_to_confirm_visits"))
    }
  }

  /**
   * Bulk delete selected visits
   */
  async bulkDeleteVisits() {
    const visitIds = Array.from(this.selectedVisitIds)

    if (
      !window.confirm(
        translate("visits.confirm_delete_count_keep_points", {
          count: visitIds.length,
        }),
      )
    ) {
      return
    }

    try {
      Toast.info(translate("messages.deleting_visits"))
      await this.api.bulkDestroyVisits(visitIds)
      Toast.success(
        translate("visits.deleted_count", { count: visitIds.length }),
      )

      this.selectedVisitIds.clear()
      await this.refreshSelectedVisits()
    } catch (error) {
      console.error("[Maps V2] Failed to delete visits:", error)
      Toast.error(translate("messages.failed_to_delete_visits"))
    }
  }

  /**
   * Replace merged visit cards with the new merged visit
   */
  replaceVisitsWithMerged(oldVisitIds, mergedVisit) {
    const container = this.controller.element.querySelector(
      ".selected-visits-list",
    )
    if (!container) return

    const mergedStartTime = new Date(mergedVisit.started_at).getTime()
    const allCards = Array.from(container.querySelectorAll(".visit-card"))

    let insertBeforeCard = null
    for (const card of allCards) {
      const cardId = parseInt(card.dataset.visitId, 10)
      if (oldVisitIds.includes(cardId)) continue

      const cardVisit = this.selectedVisits.find((v) => v.id === cardId)
      if (cardVisit) {
        const cardStartTime = new Date(cardVisit.started_at).getTime()
        if (cardStartTime > mergedStartTime) {
          insertBeforeCard = card
          break
        }
      }
    }

    oldVisitIds.forEach((id) => {
      const card = this.controller.element.querySelector(
        `.visit-card[data-visit-id="${id}"]`,
      )
      if (card) card.remove()
    })

    this.selectedVisits = this.selectedVisits.filter(
      (v) => !oldVisitIds.includes(v.id),
    )
    this.selectedVisits.push(mergedVisit)
    this.selectedVisits.sort(
      (a, b) => new Date(a.started_at) - new Date(b.started_at),
    )

    const newCardHTML = VisitCard.create(mergedVisit, { isSelected: false })

    if (insertBeforeCard) {
      insertBeforeCard.insertAdjacentHTML("beforebegin", newCardHTML)
    } else {
      container.insertAdjacentHTML("beforeend", newCardHTML)
    }

    const header = container.querySelector("h3")
    if (header) {
      header.textContent = translate("selection.visits_in_area", {
        count: this.selectedVisits.length,
      })
    }

    this.attachVisitCardListeners()
  }

  /**
   * Refresh selected visits after changes
   */
  async refreshSelectedVisits() {
    const bounds = this.selectionLayer.currentRect
    if (!bounds) return

    try {
      const visits = await this.api.fetchVisitsInArea({
        start_at: this.controller.startDateValue,
        end_at: this.controller.endDateValue,
        sw_lat:
          bounds.start.lat < bounds.end.lat ? bounds.start.lat : bounds.end.lat,
        sw_lng:
          bounds.start.lng < bounds.end.lng ? bounds.start.lng : bounds.end.lng,
        ne_lat:
          bounds.start.lat > bounds.end.lat ? bounds.start.lat : bounds.end.lat,
        ne_lng:
          bounds.start.lng > bounds.end.lng ? bounds.start.lng : bounds.end.lng,
      })

      this.displaySelectedVisits(visits)
    } catch (error) {
      console.error("[Maps V2] Failed to refresh visits:", error)
    }
  }

  /**
   * Cancel area selection
   */
  cancelAreaSelection() {
    if (this.selectionLayer) {
      this.selectionLayer.disableSelectionMode()
      this.selectionLayer.clearSelection()
    }

    if (this.selectedPointsLayer) {
      this.selectedPointsLayer.clearSelection()
    }

    if (this.controller.hasSelectedVisitsContainerTarget) {
      this.controller.selectedVisitsContainerTarget.classList.add("hidden")
      this.controller.selectedVisitsContainerTarget.innerHTML = ""
    }

    if (this.controller.hasSelectedVisitsBulkActionsTarget) {
      this.controller.selectedVisitsBulkActionsTarget.classList.add("hidden")
    }

    this.selectedVisits = []
    this.selectedVisitIds = new Set()
    this.selectedAnomalyIds = []
    if (this.controller.hasDeleteAnomaliesButtonTarget) {
      this.controller.deleteAnomaliesButtonTarget.classList.add("hidden")
    }

    if (this.controller.hasSelectAreaButtonTarget) {
      this.controller.selectAreaButtonTarget.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-5 h-5">
          <rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect>
          <path d="M9 3v18"></path>
          <path d="M15 3v18"></path>
          <path d="M3 9h18"></path>
          <path d="M3 15h18"></path>
        </svg>
        Select Area
      `
      this.controller.selectAreaButtonTarget.classList.remove("btn-error")
      this.controller.selectAreaButtonTarget.classList.add("btn", "btn-outline")
      this.controller.selectAreaButtonTarget.dataset.action =
        "click->maps--maplibre#startSelectArea"
    }

    if (this.controller.hasSelectionActionsTarget) {
      this.controller.selectionActionsTarget.classList.add("hidden")
    }

    Toast.info(translate("messages.selection_cancelled"))
  }

  async refreshAnomaliesIfEnabled() {
    const toggleOn =
      this.controller.hasAnomaliesToggleTarget &&
      this.controller.anomaliesToggleTarget.checked
    if (!toggleOn) return

    await this.controller.routesManager.refreshAnomalies({ enabled: true })
  }

  /**
   * Delete only anomaly points within the current selection. Backed by the
   * same bulkDeletePoints API as deleteSelectedPoints — the filter just
   * narrows the id list to those flagged anomaly=true server-side.
   */
  async deleteSelectedAnomalies() {
    if (this.deletingPoints) return

    const ids = this.selectedAnomalyIds
    if (!ids.length) {
      Toast.error(translate("messages.no_anomaly_points_in_selection"))
      return
    }

    const confirmed = confirm(
      translate("selection.confirm_delete_anomaly_points", {
        count: ids.length,
      }),
    )
    if (!confirmed) return

    this.deletingPoints = true
    const btn = this.controller.hasDeleteAnomaliesButtonTarget
      ? this.controller.deleteAnomaliesButtonTarget
      : null
    if (btn) btn.disabled = true

    try {
      Toast.info(translate("messages.deleting_anomaly_points"))
      const result = await this.api.bulkDeletePoints(ids)

      Toast.success(
        translate("selection.anomaly_points_deleted", { count: result.count }),
      )

      this.cancelAreaSelection()

      try {
        await this.controller.loadMapData({
          showLoading: false,
          fitBounds: false,
          showToast: false,
        })
        await this.refreshAnomaliesIfEnabled()
      } catch (reloadError) {
        console.error(
          "[Maps V2] Map refresh failed after anomaly delete:",
          reloadError,
        )
        Toast.error(translate("selection.map_refresh_failed"))
      }
    } catch (error) {
      console.error("[Maps V2] Failed to delete anomaly points:", error)
      const body = error?.body
      if (error?.status === 403 && body?.upgrade_url) {
        Toast.error(
          `${body.error || translate("selection.write_api_requires_pro")} — ${body.upgrade_url}`,
        )
      } else if (error?.status === 422 && body?.limit) {
        Toast.error(
          translate("selection.too_many_points", {
            requested: body.requested,
            limit: body.limit,
          }),
        )
      } else {
        Toast.error(
          error?.message || translate("selection.delete_points_failed"),
        )
      }
    } finally {
      this.deletingPoints = false
      if (btn) btn.disabled = false
    }
  }

  /**
   * Delete selected points
   */
  async deleteSelectedPoints() {
    if (this.deletingPoints) return

    const pointCount = this.selectedPointsLayer.getCount()
    const pointIds = this.selectedPointsLayer.getSelectedPointIds()

    if (pointIds.length === 0) {
      Toast.error(translate("messages.no_points_selected"))
      return
    }

    const confirmed = confirm(
      translate("selection.confirm_delete_points", { count: pointCount }),
    )

    if (!confirmed) return

    this.deletingPoints = true
    const deleteButton = this.controller.hasDeletePointsButtonTarget
      ? this.controller.deletePointsButtonTarget
      : null
    if (deleteButton) deleteButton.disabled = true

    try {
      Toast.info(translate("messages.deleting_points"))
      const result = await this.api.bulkDeletePoints(pointIds)

      Toast.success(
        translate("selection.points_deleted", { count: result.count }),
      )

      this.cancelAreaSelection()

      try {
        await this.controller.loadMapData({
          showLoading: false,
          fitBounds: false,
          showToast: false,
        })
        await this.refreshAnomaliesIfEnabled()
      } catch (reloadError) {
        console.error("[Maps V2] Map refresh failed after delete:", reloadError)
        Toast.error(translate("selection.map_refresh_failed"))
      }
    } catch (error) {
      console.error("[Maps V2] Failed to delete points:", error)
      const body = error?.body
      if (error?.status === 403 && body?.upgrade_url) {
        Toast.error(
          `${body.error || translate("selection.write_api_requires_pro")} — ${body.upgrade_url}`,
        )
      } else if (error?.status === 422 && body?.limit) {
        Toast.error(
          translate("selection.too_many_selected_points", {
            requested: body.requested,
            limit: body.limit,
          }),
        )
      } else {
        Toast.error(
          error?.message || translate("selection.delete_points_failed"),
        )
      }
    } finally {
      this.deletingPoints = false
      if (deleteButton) deleteButton.disabled = false
    }
  }
}
