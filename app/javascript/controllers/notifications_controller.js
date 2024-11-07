import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["badge", "list"]
  static values = { userId: Number }

  initialize() {
    this.subscription = null
  }

  connect() {
    // console.log("[Stimulus] Notifications controller connecting...")

    // Clean up any existing subscription
    if (this.subscription) {
      // console.log("[Stimulus] Cleaning up existing subscription")
      this.subscription.unsubscribe()
      this.subscription = null
    }

    // Create new subscription
    this.createSubscription()
  }

  disconnect() {
    // console.log("[Stimulus] Notifications controller disconnecting...")
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }

  createSubscription() {
    // console.log("[Stimulus] Creating new notification subscription")
    this.subscription = consumer.subscriptions.create("NotificationsChannel", {
      connected: () => {
        // console.log("[WebSocket] Connected to NotificationsChannel")
      },
      disconnected: () => {
        // console.log("[WebSocket] Disconnected from NotificationsChannel")
      },
      received: (data) => {
        // console.log("[WebSocket] Received notification:", data)
        this.animateBadge()
        this.prependNotification(data)
      }
    })
  }

  animateBadge() {
    let badge = this.hasBadgeTarget ? this.badgeTarget : null

    if (!badge) {
      badge = document.createElement("span")
      badge.className = "badge badge-xs badge-primary absolute top-0 right-0"
      badge.setAttribute("data-notifications-target", "badge")
      this.element.querySelector('.btn').appendChild(badge)
    }

    // Create ping effect div if it doesn't exist
    let pingEffect = badge.querySelector('.ping-effect')
    if (!pingEffect) {
      pingEffect = document.createElement("span")
      pingEffect.className = "ping-effect absolute inline-flex h-full w-full rounded-full animate-ping bg-primary opacity-75"
      badge.appendChild(pingEffect)
    } else {
      // Reset animation
      pingEffect.remove()
      requestAnimationFrame(() => {
        badge.appendChild(pingEffect)
      })
    }
  }

  prependNotification(notification) {
    const li = this.createNotificationListItem(notification)
    const divider = this.listTarget.querySelector(".divider")
    if (divider) {
      divider.parentNode.insertBefore(li, divider.nextSibling)
    } else {
      this.listTarget.prepend(li)
    }

    // Update the badge count
    this.updateBadge()
  }

  createNotificationListItem(notification) {
    const li = document.createElement("li")
    li.innerHTML = `
      <a href="/notifications/${notification.id}">
        ${notification.title}
        <div class="badge badge-xs justify-self-end badge-${notification.kind}"></div>
      </a>
    `
    return li
  }

  updateBadge() {
    const badgeCount = this.listTarget.children.length
    this.badgeTarget.textContent = badgeCount
    this.badgeTarget.classList.toggle("hidden", badgeCount === 0)
  }
}
