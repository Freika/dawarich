import BaseController from "./base_controller"

export default class extends BaseController {
  connect() {
    // Kept so disconnect() removes this very listener; a second bind() would
    // make a new function and leave the first one attached.
    this.boundEnforceLimit = this.enforceLimit.bind(this)
    document.addEventListener(
      "turbo:before-stream-render",
      this.boundEnforceLimit,
    )
  }

  disconnect() {
    document.removeEventListener(
      "turbo:before-stream-render",
      this.boundEnforceLimit,
    )
  }

  enforceLimit() {
    const list = document.getElementById("notifications-list")
    if (!list) return

    const items = list.querySelectorAll(".notification-item")
    if (items.length <= 10) return

    for (let i = 10; i < items.length; i++) items[i].remove()
  }
}
