import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["badge", "list"]
  static values = { userId: Number }

  initialize() {
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
    const existingNotification = this.listTarget.querySelector(`a[href="/notifications/${notification.id}"]`)
    if (existingNotification) {
      return
    }

    const li = this.createNotificationListItem(notification)
    const divider = this.listTarget.querySelector(".divider")
    if (divider) {
      divider.parentNode.insertBefore(li, divider.nextSibling)
    } else {
      this.listTarget.prepend(li)
    }

    this.updateBadge()
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
    const badgeCount = this.listTarget.querySelectorAll(".notification-item").length
    this.badgeTarget.textContent = badgeCount
    this.badgeTarget.classList.toggle("hidden", badgeCount === 0)
  }
}
