import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["container"]
  static values = { userId: Number }

  connect() {
    console.log("Controller connecting...")
    // Ensure we clean up any existing subscription
    if (this.subscription) {
      console.log("Cleaning up existing subscription")
      this.subscription.unsubscribe()
    }

    this.subscription = consumer.subscriptions.create("NotificationsChannel", {
      connected: () => {
        console.log("Connected to NotificationsChannel", this.subscription)
      },
      disconnected: () => {
        console.log("Disconnected from NotificationsChannel")
      },
      received: (data) => {
        console.log("Received notification:", data, "Subscription:", this.subscription)
        this.displayNotification(data)
      }
    })
  }

  disconnect() {
    console.log("Controller disconnecting...")
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }

  displayNotification(data) {
    console.log("Notification received:", data) // For debugging
    const notification = document.createElement("div")
    notification.classList.add("notification", `notification-${data.kind}`)
    notification.innerHTML = `<strong>${data.title}</strong>: ${data.content}`

    this.containerTarget.appendChild(notification)
    setTimeout(() => notification.remove(), 5000) // Auto-hide after 5 seconds
  }
}
