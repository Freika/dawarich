import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"
import { createMapChannel } from "maps_maplibre/channels/map_channel"
import { Toast } from "maps_maplibre/components/toast"
import {
  handleNewPoint,
  refreshLiveLayers,
  updateRecentPoint,
  zoomToPoint,
} from "maps_maplibre/utils/realtime_points"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

const LIVE_REFRESH_DELAY_MS = 1000

export default class extends Controller {
  static targets = ["liveModeToggle"]

  static values = {
    enabled: { type: Boolean, default: true },
    liveMode: { type: Boolean, default: false },
  }

  connect() {
    if (!this.enabledValue) {
      return
    }

    try {
      this.connectedChannels = new Set()
      this.liveModeEnabled = this.liveModeValue

      setTimeout(() => {
        try {
          this.setupChannels()
        } catch (error) {
          console.error(
            "[Realtime Controller] Failed to setup channels in setTimeout:",
            error,
          )
          this.updateConnectionIndicator(false)
        }
      }, 1000)

      if (this.hasLiveModeToggleTarget) {
        this.liveModeToggleTarget.checked = this.liveModeEnabled
      }
    } catch (error) {
      console.error("[Realtime Controller] Failed to initialize:", error)
    }
  }

  disconnect() {
    clearTimeout(this.liveRefreshTimer)
    this.liveRefreshTimer = null
    clearTimeout(this.trackRefreshTimer)
    this.trackRefreshTimer = null
    this.channels?.unsubscribeAll()
  }

  /**
   * Setup ActionCable channels
   * Family channel is always enabled when family feature is on
   * Points channel (live mode) is controlled by user toggle
   */
  setupChannels() {
    try {
      this.channels = createMapChannel({
        connected: this.handleConnected.bind(this),
        disconnected: this.handleDisconnected.bind(this),
        received: this.handleReceived.bind(this),
        enableLiveMode: this.liveModeEnabled,
      })
    } catch (error) {
      console.error("[Realtime Controller] Failed to setup channels:", error)
      console.error("[Realtime Controller] Error stack:", error.stack)
      this.updateConnectionIndicator(false)
    }
  }

  /**
   * Toggle live mode (new points appearing in real-time)
   */
  toggleLiveMode(event) {
    this.liveModeEnabled = event.target.checked

    this.updateRecentPointLayerVisibility()

    if (this.channels) {
      this.channels.unsubscribeAll()
    }
    this.setupChannels()

    SettingsManager.updateSetting("liveMapEnabled", this.liveModeEnabled)

    const message = this.liveModeEnabled
      ? translate("live_map.enabled")
      : translate("live_map.disabled")
    Toast.info(message)
  }

  /**
   * Update recent point layer visibility based on live mode state
   */
  updateRecentPointLayerVisibility() {
    const mapsController = this.mapsV2Controller
    if (!mapsController) {
      return
    }

    const recentPointLayer =
      mapsController.layerManager?.getLayer("recentPoint")
    if (!recentPointLayer) {
      return
    }

    if (this.liveModeEnabled) {
      recentPointLayer.show()
    } else {
      recentPointLayer.hide()
      recentPointLayer.clear()
    }
  }

  /**
   * Handle connection
   */
  handleConnected(channelName) {
    this.connectedChannels.add(channelName)

    if (this.connectedChannels.size === 1) {
      Toast.success(translate("messages.connected_to_real_time_updates"))
      this.updateConnectionIndicator(true)
    }
  }

  /**
   * Handle disconnection
   */
  handleDisconnected(channelName) {
    this.connectedChannels.delete(channelName)

    if (this.connectedChannels.size === 0) {
      Toast.warning(translate("messages.disconnected_from_real_time_updates"))
      this.updateConnectionIndicator(false)
    }
  }

  /**
   * Handle received data
   */
  handleReceived(data) {
    switch (data.type) {
      case "new_point":
        this.handleNewPoint(data.point)
        break

      case "family_location":
        this.handleFamilyLocation(data.member)
        break

      case "map_edit":
        this.handleMapEdit(data.event)
        break

      case "track_update":
        this.handleTrackUpdate(data)
        break

      // Note: notifications are handled by notifications_controller.js in the navbar
    }
  }

  handleMapEdit(event) {
    if (event?.type !== "point_moved" || !event.data) return
    const mapsController = this.mapsV2Controller
    if (!mapsController) return

    mapsController.mapDataManager?.invalidatePoints()
    const editor = mapsController.layerManager?.getLayer("map-editor")
    editor?.applyRealtime(event.data)
    mapsController.layerManager?.getLayer("points-mvt")?.refresh()
    mapsController.layerManager?.getLayer("tracks-mvt")?.refresh()
    editor?.reapplyTileFilters()
    document.dispatchEvent(
      new CustomEvent("dawarich:point-moved", { detail: event.data }),
    )
  }

  handleTrackUpdate() {
    if (this.trackRefreshTimer) return

    this.trackRefreshTimer = setTimeout(() => {
      this.trackRefreshTimer = null
      this.refreshTrackLayers()
    }, LIVE_REFRESH_DELAY_MS)
  }

  refreshTrackLayers() {
    const mapsController = this.mapsV2Controller
    if (!mapsController) return

    mapsController.layerManager?.getLayer("tracks-mvt")?.refresh()
    mapsController.layerManager?.getLayer("map-editor")?.reapplyTileFilters()
  }

  /**
   * Get the maps--maplibre controller (on same element)
   */
  get mapsV2Controller() {
    const element = this.element
    const app = this.application
    return app.getControllerForElementAndIdentifier(element, "maps--maplibre")
  }

  handleNewPoint(pointData) {
    return handleNewPoint(this, pointData)
  }

  scheduleLiveRefresh() {
    if (this.liveRefreshTimer) return

    this.liveRefreshTimer = setTimeout(() => {
      this.liveRefreshTimer = null
      this.refreshLiveLayers()
    }, LIVE_REFRESH_DELAY_MS)
  }

  refreshLiveLayers() {
    return refreshLiveLayers(this)
  }

  /**
   * Handle family member location update
   */
  handleFamilyLocation(member) {
    const mapsController = this.mapsV2Controller
    if (!mapsController) return

    const familyLayer = mapsController.layerManager?.getLayer("family")
    if (familyLayer) {
      familyLayer.updateMember(member)
    }
  }

  // Note: Notifications are handled by notifications_controller.js in the navbar

  updateRecentPoint(longitude, latitude, properties = {}) {
    return updateRecentPoint(this, longitude, latitude, properties)
  }

  zoomToPoint(longitude, latitude) {
    return zoomToPoint(this, longitude, latitude)
  }

  /**
   * Update connection indicator (no-op, badge removed)
   */
  updateConnectionIndicator(_connected) {}
}
