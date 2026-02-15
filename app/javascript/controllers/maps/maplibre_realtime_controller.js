import { Controller } from "@hotwired/stimulus"
import { createMapChannel } from "maps_maplibre/channels/map_channel"
import { Toast } from "maps_maplibre/components/toast"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

/**
 * Real-time controller
 * Manages ActionCable connection and real-time updates
 */
export default class extends Controller {
  static targets = ["liveModeToggle"]

  static values = {
    enabled: { type: Boolean, default: true },
    liveMode: { type: Boolean, default: false },
  }

  connect() {
    console.log("[Realtime Controller] Connecting...")

    if (!this.enabledValue) {
      console.log("[Realtime Controller] Disabled, skipping setup")
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
    this.channels?.unsubscribeAll()
  }

  /**
   * Setup ActionCable channels
   * Family channel is always enabled when family feature is on
   * Points channel (live mode) is controlled by user toggle
   */
  setupChannels() {
    try {
      console.log("[Realtime Controller] Setting up channels...")
      this.channels = createMapChannel({
        connected: this.handleConnected.bind(this),
        disconnected: this.handleDisconnected.bind(this),
        received: this.handleReceived.bind(this),
        enableLiveMode: this.liveModeEnabled,
      })
      console.log("[Realtime Controller] Channels setup complete")
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
      ? "Live mode enabled"
      : "Live mode disabled"
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
      Toast.success("Connected to real-time updates")
      this.updateConnectionIndicator(true)
    }
  }

  /**
   * Handle disconnection
   */
  handleDisconnected(channelName) {
    this.connectedChannels.delete(channelName)

    if (this.connectedChannels.size === 0) {
      Toast.warning("Disconnected from real-time updates")
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

      case "notification":
        this.handleNotification(data.notification)
        break

      // Note: notifications are handled by notifications_controller.js in the navbar
    }
  }

  /**
   * Get the maps--maplibre controller (on same element)
   */
  get mapsV2Controller() {
    const element = this.element
    const app = this.application
    return app.getControllerForElementAndIdentifier(element, "maps--maplibre")
  }

  /**
   * Handle new point
   * Point data is broadcast as: [lat, lon, battery, altitude, timestamp, velocity, id, country_name]
   */
  handleNewPoint(pointData) {
    const mapsController = this.mapsV2Controller
    if (!mapsController) {
      console.warn("[Realtime Controller] Maps controller not found")
      return
    }

    console.log("[Realtime Controller] Received point data:", pointData)

    const [lat, lon, battery, altitude, timestamp, velocity, id, countryName] =
      pointData

    const pointsLayer = mapsController.layerManager?.getLayer("points")
    if (!pointsLayer) {
      console.warn("[Realtime Controller] Points layer not found")
      return
    }

    const currentData = pointsLayer.data || {
      type: "FeatureCollection",
      features: [],
    }
    const features = [...(currentData.features || [])]

    features.push({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [parseFloat(lon), parseFloat(lat)],
      },
      properties: {
        id: parseInt(id, 10),
        latitude: parseFloat(lat),
        longitude: parseFloat(lon),
        battery: parseFloat(battery) || null,
        altitude: parseFloat(altitude) || null,
        timestamp: timestamp,
        velocity: parseFloat(velocity) || null,
        country_name: countryName || null,
      },
    })

    pointsLayer.update({
      type: "FeatureCollection",
      features,
    })

    console.log("[Realtime Controller] Added new point to map:", id)

    this.updateRecentPoint(parseFloat(lon), parseFloat(lat), {
      id: parseInt(id, 10),
      battery: parseFloat(battery) || null,
      altitude: parseFloat(altitude) || null,
      timestamp: timestamp,
      velocity: parseFloat(velocity) || null,
      country_name: countryName || null,
    })

    this.zoomToPoint(parseFloat(lon), parseFloat(lat))

    Toast.info("New location recorded")
  }

  /**
   * Handle family member location update
   */
  handleFamilyLocation(member) {
    const mapsController = this.mapsV2Controller
    if (!mapsController) return

    const familyLayer = mapsController.familyLayer
    if (familyLayer) {
      familyLayer.updateMember(member)
    }
  }

  // Note: Notifications are handled by notifications_controller.js in the navbar

  /**
   * Update the recent point marker
   * This marker is always visible in live mode, independent of points layer visibility
   */
  updateRecentPoint(longitude, latitude, properties = {}) {
    const mapsController = this.mapsV2Controller
    if (!mapsController) {
      console.warn("[Realtime Controller] Maps controller not found")
      return
    }

    const recentPointLayer =
      mapsController.layerManager?.getLayer("recentPoint")
    if (!recentPointLayer) {
      console.warn("[Realtime Controller] Recent point layer not found")
      return
    }

    if (this.liveModeEnabled) {
      recentPointLayer.show()
      recentPointLayer.updateRecentPoint(longitude, latitude, properties)
      console.log(
        "[Realtime Controller] Updated recent point marker:",
        longitude,
        latitude,
      )
    }
  }

  /**
   * Zoom map to a specific point
   */
  zoomToPoint(longitude, latitude) {
    const mapsController = this.mapsV2Controller
    if (!mapsController || !mapsController.map) {
      console.warn("[Realtime Controller] Map not available for zooming")
      return
    }

    const map = mapsController.map

    map.flyTo({
      center: [longitude, latitude],
      zoom: Math.max(map.getZoom(), 14),
      duration: 2000,
      essential: true,
    })

    console.log("[Realtime Controller] Zoomed to point:", longitude, latitude)
  }

  /**
   * Update connection indicator
   */
  updateConnectionIndicator(connected) {
    const indicator = document.querySelector(".connection-indicator")
    if (indicator) {
      // Show the indicator when connection is attempted
      indicator.classList.add("active")
      indicator.classList.toggle("connected", connected)
      indicator.classList.toggle("disconnected", !connected)
    }
  }
}
