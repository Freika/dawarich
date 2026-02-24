/**
 * WebSocket connection manager
 * Handles reconnection logic and connection state
 */
export class WebSocketManager {
  constructor(options = {}) {
    this.maxReconnectAttempts = options.maxReconnectAttempts || 5
    this.reconnectDelay = options.reconnectDelay || 1000
    this.reconnectAttempts = 0
    this.isConnected = false
    this.subscription = null
    this.onConnect = options.onConnect || null
    this.onDisconnect = options.onDisconnect || null
    this.onError = options.onError || null
  }

  /**
   * Connect to channel
   * @param {Object} subscription - ActionCable subscription
   */
  connect(subscription) {
    this.subscription = subscription

    // Monitor connection state
    this.subscription.connected = () => {
      this.isConnected = true
      this.reconnectAttempts = 0
      this.onConnect?.()
    }

    this.subscription.disconnected = () => {
      this.isConnected = false
      this.onDisconnect?.()
      this.attemptReconnect()
    }
  }

  /**
   * Attempt to reconnect
   */
  attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      this.onError?.(new Error("Max reconnect attempts reached"))
      return
    }

    this.reconnectAttempts++

    const delay = this.reconnectDelay * 2 ** (this.reconnectAttempts - 1)

    console.log(
      `Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`,
    )

    setTimeout(() => {
      if (!this.isConnected) {
        this.subscription?.perform("reconnect")
      }
    }, delay)
  }

  /**
   * Disconnect
   */
  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    this.isConnected = false
  }

  /**
   * Send message
   */
  send(action, data = {}) {
    if (!this.isConnected) {
      console.warn("Cannot send message: not connected")
      return
    }

    this.subscription?.perform(action, data)
  }
}
