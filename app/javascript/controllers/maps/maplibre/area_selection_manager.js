import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { SelectedPointsLayer } from "maps_maplibre/layers/selected_points_layer"
import { SelectionLayer } from "maps_maplibre/layers/selection_layer"
import { pointsToGeoJSON } from "maps_maplibre/utils/geojson_transformers"
import { anomaliesVisible } from "maps_maplibre/utils/layer_dependencies"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { SelectedVisitsPanel } from "./selected_visits_panel"

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
    this.selectedPoints = []
    this.selectedAnomalyIds = []
    this.selectedRange = null
    this._visitsPanel = null
  }

  /** The selected-visits cards and bulk actions, built on first use. */
  get visitsPanel() {
    this._visitsPanel ||= new SelectedVisitsPanel(this)
    return this._visitsPanel
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

      const range = this.selectionRange()
      this.selectedRange = range
      const [{ points, truncated }, visits] = await Promise.all([
        this.api.fetchPointsInArea({
          ...range,
          min_longitude: bounds.minLng,
          max_longitude: bounds.maxLng,
          min_latitude: bounds.minLat,
          max_latitude: bounds.maxLat,
        }),
        this.api.fetchVisitsInArea({
          ...range,
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

      this.selectedPoints = points

      // Convert points to GeoJSON and display
      if (points.length > 0) {
        const geojson = pointsToGeoJSON(points)
        this.selectedPointsLayer.updateSelectedPoints(geojson)
        this.selectedPointsLayer.show()
      }

      // Display visits in side panel and on map
      if (visits.length > 0) {
        this.visitsPanel.displaySelectedVisits(visits)
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
      if (truncated) {
        Toast.warning(
          translate("selection.truncated", {
            limit: points.length.toLocaleString(),
          }),
          8000,
        )
      }
    } catch (error) {
      console.error("[Maps V2] Failed to fetch data in area:", error)
      Toast.error(translate("messages.failed_to_fetch_data_in_selected_area"))
      this.cancelAreaSelection()
    }
  }

  selectionRange() {
    if (
      this.controller.hasSelectAllTimeCheckboxTarget &&
      this.controller.selectAllTimeCheckboxTarget.checked
    ) {
      return {}
    }

    return {
      start_at: this.controller.startDateValue,
      end_at: this.controller.endDateValue,
    }
  }

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

    this._visitsPanel?.reset()
    this.selectedPoints = []
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

  refreshPointTiles() {
    this.controller.layerManager.getLayer("points-mvt")?.refresh()
    this.controller.layerManager.getLayer("tracks-mvt")?.refresh()
  }

  async refreshAnomaliesIfEnabled() {
    if (!anomaliesVisible(SettingsManager.getSettings())) return

    await this.controller.layerVisibilityManager.refreshAnomalies({
      enabled: true,
    })
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
        this.refreshPointTiles()
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
        this.refreshPointTiles()
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
