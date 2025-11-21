import { Controller } from '@hotwired/stimulus'
import { createMapChannel } from 'maps_v2/channels/map_channel'
import { WebSocketManager } from 'maps_v2/utils/websocket_manager'
import { Toast } from 'maps_v2/components/toast'

/**
 * Real-time controller
 * Manages ActionCable connection and real-time updates
 */
export default class extends Controller {
  static targets = ['liveModeToggle']

  static values = {
    enabled: { type: Boolean, default: true },
    liveMode: { type: Boolean, default: false }
  }

  connect() {
    console.log('[Realtime Controller] Connecting...')

    if (!this.enabledValue) {
      console.log('[Realtime Controller] Disabled, skipping setup')
      return
    }

    try {
      this.connectedChannels = new Set()
      this.liveModeEnabled = false // Start with live mode disabled

      // Delay channel setup to ensure ActionCable is ready
      // This prevents race condition with page initialization
      setTimeout(() => {
        try {
          this.setupChannels()
        } catch (error) {
          console.error('[Realtime Controller] Failed to setup channels in setTimeout:', error)
          this.updateConnectionIndicator(false)
        }
      }, 1000)

      // Initialize toggle state from settings
      if (this.hasLiveModeToggleTarget) {
        this.liveModeToggleTarget.checked = this.liveModeEnabled
      }
    } catch (error) {
      console.error('[Realtime Controller] Failed to initialize:', error)
      // Don't throw - allow page to continue loading
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
      console.log('[Realtime Controller] Setting up channels...')
      this.channels = createMapChannel({
        connected: this.handleConnected.bind(this),
        disconnected: this.handleDisconnected.bind(this),
        received: this.handleReceived.bind(this),
        enableLiveMode: this.liveModeEnabled // Control points channel
      })
      console.log('[Realtime Controller] Channels setup complete')
    } catch (error) {
      console.error('[Realtime Controller] Failed to setup channels:', error)
      console.error('[Realtime Controller] Error stack:', error.stack)
      this.updateConnectionIndicator(false)
      // Don't throw - page should continue to work
    }
  }

  /**
   * Toggle live mode (new points appearing in real-time)
   */
  toggleLiveMode(event) {
    this.liveModeEnabled = event.target.checked

    // Reconnect channels with new settings
    if (this.channels) {
      this.channels.unsubscribeAll()
    }
    this.setupChannels()

    const message = this.liveModeEnabled ? 'Live mode enabled' : 'Live mode disabled'
    Toast.info(message)
  }

  /**
   * Handle connection
   */
  handleConnected(channelName) {
    this.connectedChannels.add(channelName)

    // Only show toast when at least one channel is connected
    if (this.connectedChannels.size === 1) {
      Toast.success('Connected to real-time updates')
      this.updateConnectionIndicator(true)
    }
  }

  /**
   * Handle disconnection
   */
  handleDisconnected(channelName) {
    this.connectedChannels.delete(channelName)

    // Show warning only when all channels are disconnected
    if (this.connectedChannels.size === 0) {
      Toast.warning('Disconnected from real-time updates')
      this.updateConnectionIndicator(false)
    }
  }

  /**
   * Handle received data
   */
  handleReceived(data) {
    switch (data.type) {
      case 'new_point':
        this.handleNewPoint(data.point)
        break

      case 'family_location':
        this.handleFamilyLocation(data.member)
        break

      case 'notification':
        this.handleNotification(data.notification)
        break
    }
  }

  /**
   * Get the maps-v2 controller (on same element)
   */
  get mapsV2Controller() {
    const element = this.element
    const app = this.application
    return app.getControllerForElementAndIdentifier(element, 'maps-v2')
  }

  /**
   * Handle new point
   */
  handleNewPoint(point) {
    const mapsController = this.mapsV2Controller
    if (!mapsController) {
      console.warn('[Realtime Controller] Maps V2 controller not found')
      return
    }

    // Add point to map
    const pointsLayer = mapsController.pointsLayer
    if (pointsLayer) {
      const currentData = pointsLayer.data
      const features = currentData.features || []

      features.push({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [point.longitude, point.latitude]
        },
        properties: point
      })

      pointsLayer.update({
        type: 'FeatureCollection',
        features
      })

      Toast.info('New location recorded')
    }
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

  /**
   * Handle notification
   */
  handleNotification(notification) {
    Toast.info(notification.message || 'New notification')
  }

  /**
   * Update connection indicator
   */
  updateConnectionIndicator(connected) {
    const indicator = document.querySelector('.connection-indicator')
    if (indicator) {
      indicator.classList.toggle('connected', connected)
      indicator.classList.toggle('disconnected', !connected)
    }
  }
}
