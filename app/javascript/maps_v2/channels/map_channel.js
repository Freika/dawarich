import consumer from '../../channels/consumer'

/**
 * Create map channel subscription for maps_v2
 * Wraps the existing FamilyLocationsChannel and other channels for real-time updates
 * @param {Object} options - { received, connected, disconnected, enableLiveMode }
 * @returns {Object} Subscriptions object with multiple channels
 */
export function createMapChannel(options = {}) {
  const { enableLiveMode = false, ...callbacks } = options
  const subscriptions = {
    family: null,
    points: null,
    notifications: null
  }

  console.log('[MapChannel] Creating channels with enableLiveMode:', enableLiveMode)

  // Defensive check - consumer might not be available
  if (!consumer) {
    console.warn('[MapChannel] ActionCable consumer not available')
    return {
      subscriptions,
      unsubscribeAll() {}
    }
  }

  // Subscribe to family locations if family feature is enabled
  try {
    const familyFeaturesElement = document.querySelector('[data-family-members-features-value]')
    const features = familyFeaturesElement ? JSON.parse(familyFeaturesElement.dataset.familyMembersFeaturesValue) : {}

    if (features.family) {
      subscriptions.family = consumer.subscriptions.create('FamilyLocationsChannel', {
        connected() {
          console.log('FamilyLocationsChannel connected')
          callbacks.connected?.('family')
        },

        disconnected() {
          console.log('FamilyLocationsChannel disconnected')
          callbacks.disconnected?.('family')
        },

        received(data) {
          console.log('FamilyLocationsChannel received:', data)
          callbacks.received?.({
            type: 'family_location',
            member: data
          })
        }
      })
    }
  } catch (error) {
    console.warn('[MapChannel] Failed to subscribe to family channel:', error)
  }

  // Subscribe to points channel for real-time point updates (only if live mode is enabled)
  if (enableLiveMode) {
    try {
      subscriptions.points = consumer.subscriptions.create('PointsChannel', {
        connected() {
          console.log('PointsChannel connected')
          callbacks.connected?.('points')
        },

        disconnected() {
          console.log('PointsChannel disconnected')
          callbacks.disconnected?.('points')
        },

        received(data) {
          console.log('PointsChannel received:', data)
          callbacks.received?.({
            type: 'new_point',
            point: data
          })
        }
      })
    } catch (error) {
      console.warn('[MapChannel] Failed to subscribe to points channel:', error)
    }
  } else {
    console.log('[MapChannel] Live mode disabled, not subscribing to PointsChannel')
  }

  // Subscribe to notifications channel
  try {
    subscriptions.notifications = consumer.subscriptions.create('NotificationsChannel', {
      connected() {
        console.log('NotificationsChannel connected')
        callbacks.connected?.('notifications')
      },

      disconnected() {
        console.log('NotificationsChannel disconnected')
        callbacks.disconnected?.('notifications')
      },

      received(data) {
        console.log('NotificationsChannel received:', data)
        callbacks.received?.({
          type: 'notification',
          notification: data
        })
      }
    })
  } catch (error) {
    console.warn('[MapChannel] Failed to subscribe to notifications channel:', error)
  }

  return {
    subscriptions,
    unsubscribeAll() {
      Object.values(subscriptions).forEach(sub => sub?.unsubscribe())
    }
  }
}
