import BaseController from "./base_controller"
import consumer from "../channels/consumer"

export default class extends BaseController {
  static targets = ["badge", "list"]
  static values = { userId: Number }

  initialize() {
    super.initialize()
    this.subscription = null
  }

  connect() {
    // Clean up any existing subscription
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }

    this.createSubscription()
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }

  createSubscription() {
    this.subscription = consumer.subscriptions.create("NotificationsChannel", {
      connected: () => {
        // console.log("[WebSocket] Connected to NotificationsChannel")
      },
      disconnected: () => {
        // console.log("[WebSocket] Disconnected from NotificationsChannel")
      },
      received: (data) => {
        // console.log("[WebSocket] Received notification:", data)
        this.prependNotification(data)
      }
    })
  }

  prependNotification(notification) {
    if (!this.hasListTarget) {
      this.updateBadge()
      return
    }

    const existingNotification = this.listTarget.querySelector(`a[href="/notifications/${notification.id}"]`)
    if (existingNotification) {
      return
    }

    // Create divider and notification item to match server-side structure
    const divider = this.createDivider()
    const li = this.createNotificationListItem(notification)

    // Find the "See all" link to determine where to insert
    const seeAllLink = this.listTarget.querySelector('li:first-child')
    if (seeAllLink) {
      // Insert after the "See all" link
      seeAllLink.insertAdjacentElement('afterend', divider)
      divider.insertAdjacentElement('afterend', li)
    } else {
      // Fallback: prepend to list
      this.listTarget.prepend(divider)
      this.listTarget.prepend(li)
    }

    // Enforce limit of 10 notification items (excluding the "See all" link)
    this.enforceNotificationLimit()

    this.updateBadge()
  }

  createDivider() {
    const divider = document.createElement("div")
    divider.className = "divider p-0 m-0"
    return divider
  }

  enforceNotificationLimit() {
    const limit = 10
    const notificationItems = this.listTarget.querySelectorAll('.notification-item')

    // Remove excess notifications if we exceed the limit
    if (notificationItems.length > limit) {
      // Remove the oldest notifications (from the end of the list)
      for (let i = limit; i < notificationItems.length; i++) {
        const itemToRemove = notificationItems[i]
        // Also remove the divider that comes before it
        const previousSibling = itemToRemove.previousElementSibling
        if (previousSibling && previousSibling.classList.contains('divider')) {
          previousSibling.remove()
        }
        itemToRemove.remove()
      }
    }
  }

  createNotificationListItem(notification) {
    const li = document.createElement("li")
    li.className = "notification-item"
    li.innerHTML = `
      <a href="/notifications/${notification.id}">
        ${notification.title}
        <div class="badge badge-xs justify-self-end badge-${notification.kind}"></div>
      </a>
    `
    return li
  }

  updateBadge() {
    if (!this.hasBadgeTarget) return

    if (this.hasListTarget) {
      const badgeCount = this.listTarget.querySelectorAll(".notification-item").length
      this.badgeTarget.textContent = badgeCount
      this.badgeTarget.classList.toggle("hidden", badgeCount === 0)
    }
  }
}
