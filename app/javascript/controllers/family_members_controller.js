import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import Flash from "./flash_controller"

export default class extends Controller {
  static targets = []

  static values = {
    features: Object,
    userTheme: String,
    timezone: String,
  }

  connect() {
    console.log("Family members controller connected")

    // Wait for maps controller to be ready
    this.waitForMap()
  }

  disconnect() {
    this.cleanup()
    console.log("Family members controller disconnected")
  }

  waitForMap() {
    // Find the maps controller element
    const mapElement = document.querySelector('[data-controller*="maps"]')
    if (!mapElement) {
      console.warn("Maps controller element not found")
      return
    }

    // Wait for the maps controller to be initialized
    const checkMapReady = () => {
      if (window.mapsController?.map) {
        this.initializeFamilyFeatures()
      } else {
        setTimeout(checkMapReady, 100)
      }
    }

    checkMapReady()
  }

  initializeFamilyFeatures() {
    this.map = window.mapsController.map

    if (!this.map) {
      console.warn("Map not available for family members controller")
      return
    }

    // Initialize family member markers layer
    this.familyMarkersLayer = L.layerGroup()
    this.familyMemberLocations = {} // Object keyed by user_id for efficient updates
    this.familyMarkers = {} // Store marker references by user_id

    // Expose controller globally for ActionCable channel
    window.familyMembersController = this

    // Register event listeners BEFORE adding to layer control
    // so the overlayadd handler is ready when layer.addTo(map) fires
    this.setupEventListeners()

    // Add to layer control (dispatches family:layer:ready,
    // which may trigger layer.addTo() and overlayadd)
    this.addToLayerControl()
  }

  createFamilyMarkers() {
    // Clear existing family markers
    if (this.familyMarkersLayer) {
      this.familyMarkersLayer.clearLayers()
    }

    // Clear marker references
    this.familyMarkers = {}

    // Only proceed if family feature is enabled and we have family member locations
    if (
      !this.featuresValue.family ||
      !this.familyMemberLocations ||
      Object.keys(this.familyMemberLocations).length === 0
    ) {
      return
    }

    const bounds = []

    Object.values(this.familyMemberLocations).forEach((location) => {
      if (!location || !location.latitude || !location.longitude) {
        return
      }

      // Get the first letter of the email or use '?' as fallback
      const emailInitial =
        location.email_initial ||
        location.email?.charAt(0)?.toUpperCase() ||
        "?"

      // Check if this is a recent update (within last 5 minutes)
      const isRecent = this.isRecentUpdate(location.updated_at)
      const markerClass = isRecent
        ? "family-member-marker family-member-marker-recent"
        : "family-member-marker"

      // Create a distinct marker for family members with email initial
      const familyMarker = L.marker([location.latitude, location.longitude], {
        icon: L.divIcon({
          html: `<div style="background-color: #10B981; color: white; border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; border: 2px solid white; box-shadow: 0 2px 4px rgba(0,0,0,0.2); font-size: 14px; font-weight: bold; font-family: system-ui, -apple-system, sans-serif;">${emailInitial}</div>`,
          iconSize: [24, 24],
          iconAnchor: [12, 12],
          className: markerClass,
        }),
      })

      // Format timestamp for display
      const timezone = this.timezoneValue || "UTC"
      const lastSeen = new Date(location.updated_at).toLocaleString("en-US", {
        timeZone: timezone,
      })

      // Create small tooltip that shows automatically
      const tooltipContent = this.createTooltipContent(
        lastSeen,
        location.battery,
      )
      const _tooltip = familyMarker.bindTooltip(tooltipContent, {
        permanent: true,
        direction: "top",
        offset: [0, -12],
        className: "family-member-tooltip",
      })

      // Create detailed popup that shows on click
      const popupContent = this.createPopupContent(location, lastSeen)
      familyMarker.bindPopup(popupContent)

      // Hide tooltip when popup opens, show when popup closes
      familyMarker.on("popupopen", () => {
        familyMarker.closeTooltip()
      })
      familyMarker.on("popupclose", () => {
        familyMarker.openTooltip()
      })

      this.familyMarkersLayer.addLayer(familyMarker)

      // Store marker reference by user_id for efficient updates
      this.familyMarkers[location.user_id] = familyMarker

      // Add to bounds array for auto-zoom
      bounds.push([location.latitude, location.longitude])
    })

    // Store bounds for later use
    this.familyMemberBounds = bounds
  }

  // Update a single family member's location in real-time
  updateSingleMemberLocation(locationData) {
    if (!this.featuresValue.family) return
    if (!locationData || !locationData.user_id) return

    // Update stored location data
    this.familyMemberLocations[locationData.user_id] = locationData

    // If the Family Members layer is not currently visible, just store the data
    if (!this.map.hasLayer(this.familyMarkersLayer)) {
      return
    }

    // Get existing marker for this user
    const existingMarker = this.familyMarkers[locationData.user_id]

    if (existingMarker) {
      // Update existing marker position and content
      existingMarker.setLatLng([locationData.latitude, locationData.longitude])

      // Update marker icon with pulse animation for recent updates
      const emailInitial =
        locationData.email_initial ||
        locationData.email?.charAt(0)?.toUpperCase() ||
        "?"
      const isRecent = this.isRecentUpdate(locationData.updated_at)
      const markerClass = isRecent
        ? "family-member-marker family-member-marker-recent"
        : "family-member-marker"

      const newIcon = L.divIcon({
        html: `<div style="background-color: #10B981; color: white; border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; border: 2px solid white; box-shadow: 0 2px 4px rgba(0,0,0,0.2); font-size: 14px; font-weight: bold; font-family: system-ui, -apple-system, sans-serif;">${emailInitial}</div>`,
        iconSize: [24, 24],
        iconAnchor: [12, 12],
        className: markerClass,
      })
      existingMarker.setIcon(newIcon)

      // Update tooltip content
      const timezone = this.timezoneValue || "UTC"
      const lastSeen = new Date(locationData.updated_at).toLocaleString(
        "en-US",
        { timeZone: timezone },
      )
      const tooltipContent = this.createTooltipContent(
        lastSeen,
        locationData.battery,
      )
      existingMarker.setTooltipContent(tooltipContent)

      // Update popup content
      const popupContent = this.createPopupContent(locationData, lastSeen)
      existingMarker.setPopupContent(popupContent)
    } else {
      // Create new marker for this user
      this.createSingleFamilyMarker(locationData)
    }
  }

  // Check if location was updated within the last 5 minutes
  isRecentUpdate(updatedAt) {
    const updateTime = new Date(updatedAt)
    const now = new Date()
    const diffMinutes = (now - updateTime) / 1000 / 60
    return diffMinutes < 5
  }

  // Create a marker for a single family member
  createSingleFamilyMarker(location) {
    if (!location || !location.latitude || !location.longitude) return

    const emailInitial =
      location.email_initial || location.email?.charAt(0)?.toUpperCase() || "?"
    const isRecent = this.isRecentUpdate(location.updated_at)
    const markerClass = isRecent
      ? "family-member-marker family-member-marker-recent"
      : "family-member-marker"

    const familyMarker = L.marker([location.latitude, location.longitude], {
      icon: L.divIcon({
        html: `<div style="background-color: #10B981; color: white; border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; border: 2px solid white; box-shadow: 0 2px 4px rgba(0,0,0,0.2); font-size: 14px; font-weight: bold; font-family: system-ui, -apple-system, sans-serif;">${emailInitial}</div>`,
        iconSize: [24, 24],
        iconAnchor: [12, 12],
        className: markerClass,
      }),
    })

    const timezone = this.timezoneValue || "UTC"
    const lastSeen = new Date(location.updated_at).toLocaleString("en-US", {
      timeZone: timezone,
    })

    const tooltipContent = this.createTooltipContent(lastSeen, location.battery)
    familyMarker.bindTooltip(tooltipContent, {
      permanent: true,
      direction: "top",
      offset: [0, -12],
      className: "family-member-tooltip",
    })

    const popupContent = this.createPopupContent(location, lastSeen)
    familyMarker.bindPopup(popupContent)

    familyMarker.on("popupopen", () => {
      familyMarker.closeTooltip()
    })
    familyMarker.on("popupclose", () => {
      familyMarker.openTooltip()
    })

    this.familyMarkersLayer.addLayer(familyMarker)
    this.familyMarkers[location.user_id] = familyMarker
  }

  createTooltipContent(lastSeen, battery) {
    const batteryInfo =
      battery !== null && battery !== undefined ? ` | Battery: ${battery}%` : ""
    return `Last seen: ${lastSeen}${batteryInfo}`
  }

  createPopupContent(location, lastSeen) {
    const isDark = this.userThemeValue === "dark"
    const bgColor = isDark ? "#1f2937" : "#ffffff"
    const textColor = isDark ? "#f9fafb" : "#111827"
    const mutedColor = isDark ? "#9ca3af" : "#6b7280"

    const emailInitial =
      location.email_initial || location.email?.charAt(0)?.toUpperCase() || "?"

    // Battery display with icon
    const battery = location.battery
    const batteryStatus = location.battery_status
    let batteryDisplay = ""

    if (battery !== null && battery !== undefined) {
      // Determine battery color based on level and status
      let batteryColor = "#10B981" // green
      if (batteryStatus === "charging") {
        batteryColor = battery <= 50 ? "#F59E0B" : "#10B981" // orange if low, green if high
      } else if (battery <= 20) {
        batteryColor = "#EF4444" // red
      } else if (battery <= 50) {
        batteryColor = "#F59E0B" // orange
      }

      // Helper function to get appropriate Lucide battery icon
      const getBatteryIcon = (battery, batteryStatus, batteryColor) => {
        const baseAttrs = `width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="${batteryColor}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"`

        // Charging icon
        if (batteryStatus === "charging") {
          return `<svg xmlns="http://www.w3.org/2000/svg" ${baseAttrs}><path d="m11 7-3 5h4l-3 5"/><path d="M14.856 6H16a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.935"/><path d="M22 14v-4"/><path d="M5.14 18H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h2.936"/></svg>`
        }

        // Full battery
        if (battery === 100 || batteryStatus === "full") {
          return `<svg xmlns="http://www.w3.org/2000/svg" ${baseAttrs}><path d="M10 10v4"/><path d="M14 10v4"/><path d="M22 14v-4"/><path d="M6 10v4"/><rect x="2" y="6" width="16" height="12" rx="2"/></svg>`
        }

        // Low battery (≤20%)
        if (battery <= 20) {
          return `<svg xmlns="http://www.w3.org/2000/svg" ${baseAttrs}><path d="M22 14v-4"/><path d="M6 14v-4"/><rect x="2" y="6" width="16" height="12" rx="2"/></svg>`
        }

        // Medium battery (21-50%)
        if (battery <= 50) {
          return `<svg xmlns="http://www.w3.org/2000/svg" ${baseAttrs}><path d="M10 14v-4"/><path d="M22 14v-4"/><path d="M6 14v-4"/><rect x="2" y="6" width="16" height="12" rx="2"/></svg>`
        }

        // High battery (>50%, default to full)
        return `<svg xmlns="http://www.w3.org/2000/svg" ${baseAttrs}><path d="M10 10v4"/><path d="M14 10v4"/><path d="M22 14v-4"/><path d="M6 10v4"/><rect x="2" y="6" width="16" height="12" rx="2"/></svg>`
      }

      const batteryIcon = getBatteryIcon(battery, batteryStatus, batteryColor)

      batteryDisplay = `
        <p style="margin: 0 0 8px 0; font-size: 13px;">
          ${batteryIcon}<strong>Battery:</strong> ${battery}%${batteryStatus ? ` (${batteryStatus})` : ""}
        </p>
      `
    }

    return `
      <div class="family-member-popup" style="background-color: ${bgColor}; color: ${textColor}; padding: 12px; border-radius: 8px; min-width: 220px;">
        <h3 style="margin: 0 0 12px 0; color: #10B981; font-size: 15px; font-weight: bold; display: flex; align-items: center; gap: 8px;">
          <span style="background-color: #10B981; color: white; border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; font-size: 14px; font-weight: bold;">${emailInitial}</span>
          Family Member
        </h3>
        <p style="margin: 0 0 8px 0; font-size: 13px;">
          <strong>Email:</strong> ${location.email || "Unknown"}
        </p>
        <p style="margin: 0 0 8px 0; font-size: 13px;">
          <strong>Coordinates:</strong><br/>
          ${location.latitude.toFixed(6)}, ${location.longitude.toFixed(6)}
        </p>
        ${batteryDisplay}
        <p style="margin: 0; font-size: 12px; color: ${mutedColor}; padding-top: 8px; border-top: 1px solid ${isDark ? "#374151" : "#e5e7eb"};">
          <strong>Last seen:</strong> ${lastSeen}
        </p>
      </div>
    `
  }

  addToLayerControl() {
    // Add family markers layer to the maps controller's layer control
    if (window.mapsController?.layerControl && this.familyMarkersLayer) {
      // We need to recreate the layer control to include our new layer
      this.updateMapsControllerLayerControl()
    }
  }

  updateMapsControllerLayerControl() {
    const mapsController = window.mapsController
    if (
      !mapsController ||
      typeof mapsController.updateLayerControl !== "function"
    )
      return

    // Use the maps controller's helper method to update layer control
    mapsController.updateLayerControl({
      "Family Members": this.familyMarkersLayer,
    })

    // Dispatch event to notify that Family Members layer is now available
    document.dispatchEvent(
      new CustomEvent("family:layer:ready", {
        detail: { layer: this.familyMarkersLayer },
      }),
    )
  }

  setupEventListeners() {
    // Listen for family data updates (for real-time updates in the future)
    document.addEventListener("family:locations:updated", (event) => {
      this.familyMemberLocations = event.detail.locations
      this.createFamilyMarkers()
    })

    // Listen for theme changes
    document.addEventListener("theme:changed", (event) => {
      this.userThemeValue = event.detail.theme
      // Recreate popups with new theme
      this.createFamilyMarkers()
    })

    // Listen for layer control events
    this.setupLayerControlEvents()
  }

  setupLayerControlEvents() {
    if (!this.map) return

    // Listen for when the Family Members layer is added
    this.map.on("overlayadd", (event) => {
      if (
        event.name === "Family Members" &&
        event.layer === this.familyMarkersLayer
      ) {
        // Refresh locations and zoom after data is loaded
        this.refreshFamilyLocations().then(() => {
          this.zoomToFitAllMembers()
        })

        // Set up periodic refresh while layer is active
        this.startPeriodicRefresh()
      }
    })

    // Listen for when the Family Members layer is removed
    this.map.on("overlayremove", (event) => {
      if (
        event.name === "Family Members" &&
        event.layer === this.familyMarkersLayer
      ) {
        // Stop periodic refresh when layer is disabled
        this.stopPeriodicRefresh()
      }
    })
  }

  zoomToFitAllMembers() {
    if (!this.familyMemberBounds || this.familyMemberBounds.length === 0) {
      return
    }

    // If there's only one member, center on them with a reasonable zoom
    if (this.familyMemberBounds.length === 1) {
      this.map.setView(this.familyMemberBounds[0], 13)
      return
    }

    // For multiple members, fit bounds to show all of them
    const bounds = L.latLngBounds(this.familyMemberBounds)
    this.map.fitBounds(bounds, {
      padding: [50, 50], // Add padding around the edges
      maxZoom: 15, // Don't zoom in too close
    })
  }

  startPeriodicRefresh() {
    // Clear any existing refresh interval
    this.stopPeriodicRefresh()

    // Refresh family locations every 60 seconds while layer is active (as fallback to real-time)
    this.refreshInterval = setInterval(() => {
      if (this.map?.hasLayer(this.familyMarkersLayer)) {
        this.refreshFamilyLocations()
      } else {
        // Layer is no longer active, stop refreshing
        this.stopPeriodicRefresh()
      }
    }, 60000) // 60 seconds (real-time updates via ActionCable are primary)
  }

  stopPeriodicRefresh() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
      this.refreshInterval = null
    }
  }

  // Method to manually update family member locations (for API calls)
  updateFamilyLocations(locations) {
    // Convert array to object keyed by user_id
    if (Array.isArray(locations)) {
      this.familyMemberLocations = {}
      locations.forEach((location) => {
        if (location.user_id) {
          this.familyMemberLocations[location.user_id] = location
        }
      })
    } else {
      this.familyMemberLocations = locations
    }

    this.createFamilyMarkers()

    // Dispatch event for other controllers that might be interested
    document.dispatchEvent(
      new CustomEvent("family:locations:updated", {
        detail: { locations: this.familyMemberLocations },
      }),
    )
  }

  // Method to refresh family locations from API
  async refreshFamilyLocations() {
    if (!window.mapsController?.apiKey) {
      console.warn("API key not available for family locations refresh")
      return
    }

    try {
      const response = await fetch(
        `/api/v1/families/locations?api_key=${window.mapsController.apiKey}`,
        {
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
          },
        },
      )

      if (!response.ok) {
        if (response.status === 403) {
          console.warn("Family feature not enabled or user not in family")
          return
        }
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      this.updateFamilyLocations(data.locations || [])

      // Show user feedback if this was a manual refresh
      if (this.showUserFeedback) {
        const count = data.locations?.length || 0
        this.showFlashMessageToUser(
          "notice",
          `Family locations updated (${count} members)`,
        )
        this.showUserFeedback = false // Reset flag
      }
    } catch (error) {
      console.error("Error refreshing family locations:", error)

      // Show error to user if this was a manual refresh
      if (this.showUserFeedback) {
        this.showFlashMessageToUser(
          "error",
          "Failed to refresh family locations",
        )
        this.showUserFeedback = false // Reset flag
      }
    }
  }

  // Helper method to show flash messages using the imported helper
  showFlashMessageToUser(type, message) {
    Flash.show(type, message)
  }

  // Method for manual refresh with user feedback
  async manualRefreshFamilyLocations() {
    this.showUserFeedback = true // Enable user feedback for this refresh
    await this.refreshFamilyLocations()
  }

  cleanup() {
    // Stop periodic refresh
    this.stopPeriodicRefresh()

    // Remove family markers layer from map if it exists
    if (
      this.familyMarkersLayer &&
      this.map &&
      this.map.hasLayer(this.familyMarkersLayer)
    ) {
      this.map.removeLayer(this.familyMarkersLayer)
    }

    // Remove map event listeners
    if (this.map) {
      this.map.off("overlayadd")
      this.map.off("overlayremove")
    }

    // Remove document event listeners
    document.removeEventListener(
      "family:locations:updated",
      this.handleLocationUpdates,
    )
    document.removeEventListener("theme:changed", this.handleThemeChange)
  }

  // Expose layer for external access
  getFamilyMarkersLayer() {
    return this.familyMarkersLayer
  }

  // Check if family features are enabled
  isFamilyFeatureEnabled() {
    return this.featuresValue.family === true
  }

  // Get family marker count
  getFamilyMemberCount() {
    return this.familyMemberLocations
      ? Object.keys(this.familyMemberLocations).length
      : 0
  }
}
