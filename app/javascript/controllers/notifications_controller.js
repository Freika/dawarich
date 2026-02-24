import BaseController from "./base_controller"

export default class extends BaseController {
  connect() {
    document.addEventListener(
      "turbo:before-stream-render",
      this.enforceLimit.bind(this),
    )
  }

  disconnect() {
    document.removeEventListener(
      "turbo:before-stream-render",
      this.enforceLimit.bind(this),
    )
  }

  enforceLimit() {
    const list = document.getElementById("notifications-list")
    if (!list) return

    const items = list.querySelectorAll(".notification-item")
    if (items.length <= 10) return

    for (let i = 10; i < items.length; i++) {
      const item = items[i]
      const divider = item.previousElementSibling
      if (divider?.classList.contains("divider")) divider.remove()
      item.remove()
    }
  }
}
