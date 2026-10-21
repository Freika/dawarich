export class Toast {
  static container = null

  static init() {
    if (Toast.container) return

    Toast.container = document.createElement("div")
    Toast.container.className = "toast-container"
    Toast.container.style.cssText = `
      position: fixed;
      top: 20px;
      right: 20px;
      z-index: 9999;
      display: flex;
      flex-direction: column;
      width: min(300px, calc(100vw - 40px));
      max-width: calc(100vw - 40px);
      overflow-x: clip;
      gap: 12px;
      pointer-events: none;
    `
    document.body.appendChild(Toast.container)
    Toast.addStyles()
  }

  static addStyles() {
    if (document.getElementById("toast-styles")) return

    const style = document.createElement("style")
    style.id = "toast-styles"
    style.textContent = `
      @keyframes toast-slide-in {
        from {
          transform: translateX(400px);
          opacity: 0;
        }
        to {
          transform: translateX(0);
          opacity: 1;
        }
      }

      @keyframes toast-slide-out {
        from {
          transform: translateX(0);
          opacity: 1;
        }
        to {
          transform: translateX(400px);
          opacity: 0;
        }
      }

      .toast-container > .toast {
        position: relative;
        inset: auto;
        min-width: 0;
        white-space: normal;
        flex-direction: row;
        flex-wrap: wrap;
        pointer-events: none;
        animation: toast-slide-in 0.3s ease-out;
      }

      .toast-container > .toast button {
        pointer-events: auto;
      }

      .toast-container > .toast.removing {
        animation: toast-slide-out 0.3s ease-out;
      }
    `
    document.head.appendChild(style)
  }

  static show(message, type = "info", duration = 3000, action = null) {
    Toast.init()

    const toast = document.createElement("div")
    toast.className = `toast toast-${type}`
    const messageElement = document.createElement("span")
    messageElement.style.cssText = "min-width: 0; overflow-wrap: anywhere;"
    messageElement.textContent = message
    toast.appendChild(messageElement)

    toast.style.cssText = `
      padding: 12px 20px;
      background: ${Toast.getBackgroundColor(type)};
      color: white;
      border-radius: 8px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
      font-size: 14px;
      font-weight: 500;
      max-width: 100%;
      line-height: 1.4;
      display: flex;
      align-items: center;
      gap: 12px;
    `

    if (action?.label && action?.callback) {
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = action.label
      button.style.cssText = `
        border: 1px solid rgba(255, 255, 255, 0.8);
        border-radius: 6px;
        padding: 4px 8px;
        color: white;
        font-weight: 700;
        min-width: 0;
        max-width: 100%;
        white-space: normal;
        overflow-wrap: anywhere;
      `
      button.addEventListener("click", () => {
        Toast.dismiss(toast)
        action.callback()
      })
      toast.appendChild(button)
    }

    Toast.container.appendChild(toast)
    if (duration > 0) {
      setTimeout(() => {
        Toast.dismiss(toast)
      }, duration)
    }

    return toast
  }

  static dismiss(toast) {
    if (!toast?.parentNode) return

    toast.classList.add("removing")
    setTimeout(() => {
      toast.remove()
    }, 300)
  }

  static getBackgroundColor(type) {
    const colors = {
      success: "#22c55e",
      error: "#ef4444",
      warning: "#f59e0b",
      info: "#3b82f6",
    }
    return colors[type] || colors.info
  }

  static success(message, duration = 3000) {
    return Toast.show(message, "success", duration)
  }

  static error(message, duration = 4000) {
    return Toast.show(message, "error", duration)
  }

  static retry(message, label, callback) {
    return Toast.show(message, "error", 0, { label, callback })
  }

  static warning(message, duration = 3500) {
    return Toast.show(message, "warning", duration)
  }

  static info(message, duration = 3000) {
    return Toast.show(message, "info", duration)
  }

  static clearAll() {
    if (!Toast.container) return

    const toasts = Toast.container.querySelectorAll(".toast")
    toasts.forEach((toast) => {
      Toast.dismiss(toast)
    })
  }
}
