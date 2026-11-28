import { translate } from "i18n"
import { deletePlace } from "maps_maplibre/components/place_actions"
import { Toast } from "maps_maplibre/components/toast"

/** The map panel's info card and the delete / mark-valid buttons it shows. */
export class InfoPanel {
  constructor(controller) {
    this.controller = controller
  }

  show(title, content, actions = []) {
    if (!this.controller.hasInfoDisplayTarget) return

    // Set title
    this.controller.infoTitleTarget.textContent = title

    // Set content
    this.controller.infoContentTarget.innerHTML = content

    // Set actions
    if (actions.length > 0) {
      this.controller.infoActionsTarget.innerHTML = actions
        .map((action) => {
          if (action.type === "button") {
            // For button actions (modals, etc.), create a button with data-action
            // Use error styling for delete buttons
            const buttonClass =
              action.handler === "handleDelete"
                ? "btn btn-sm btn-error"
                : "btn btn-sm btn-primary"
            return `<button class="${buttonClass}" data-action="click->maps--maplibre#${action.handler}" data-id="${action.id}" data-entity-type="${action.entityType}">${action.label}</button>`
          } else {
            // For link actions, keep the original behavior
            return `<a href="${action.url}" class="btn btn-sm btn-primary">${action.label}</a>`
          }
        })
        .join("")
    } else {
      this.controller.infoActionsTarget.innerHTML = ""
    }

    // Show info display
    this.controller.infoDisplayTarget.classList.remove("hidden")

    // Switch to tools tab and open panel
    this.controller.switchToToolsTab()
  }

  close(options = {}) {
    if (!this.controller.hasInfoDisplayTarget) return
    this.controller.infoDisplayTarget.classList.add("hidden")

    if (options.clearSelection !== false && this.controller.eventHandlers) {
      this.controller.eventHandlers.clearTrackSelection()
      this.controller.eventHandlers.clearPointSelection()
    }
  }

  /**
   * Handle delete action from info display
   */
  handleDelete(event) {
    const button = event.currentTarget
    const id = button.dataset.id
    const entityType = button.dataset.entityType

    switch (entityType) {
      case "point":
        this.deletePoint(id)
        break
      case "place":
        return deletePlace(this.controller, id)
      default:
        console.warn("[Maps V2] Unknown entity type for delete:", entityType)
    }
  }

  /** Delete a point, then invalidate the tile-backed presentation. */
  async deletePoint(pointId) {
    const confirmed = confirm(translate("map.confirm_delete_point_permanently"))
    if (!confirmed) return

    try {
      await this.controller.api.deletePoint(pointId)
      this.controller.mapDataManager?.invalidatePoints()
      this.controller.layerManager.getLayer("map-editor")?.close()
      this.controller.layerManager.getLayer("points-mvt")?.refresh()
      this.controller.layerManager.getLayer("tracks-mvt")?.refresh()
      this.controller.layerManager.getLayer("scratch")?.retryMembership()
      this.close()
      Toast.success(translate("messages.point_deleted_successfully"))
    } catch (_error) {
      Toast.error(translate("messages.failed_to_delete_point"))
    }
  }

  /** Mark an anomaly as correct, then reload anomalies, points and tracks. */
  async markPointValid(event) {
    try {
      await this.controller.api.markPointValid(event.currentTarget.dataset.id)
      this.controller.mapDataManager?.invalidatePoints()
      this.controller.layerManager.getLayer("points-mvt")?.refresh()
      this.controller.layerManager.getLayer("tracks-mvt")?.refresh()
      this.controller.layerVisibilityManager.refreshAnomalies({ enabled: true })
      this.close()
      Toast.success(translate("messages.point_marked_valid"))
    } catch (_error) {
      Toast.error(translate("messages.failed_to_mark_point_valid"))
    }
  }
}
