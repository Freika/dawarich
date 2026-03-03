/**
 * Toast notification system
 * Displays temporary notifications in the top-right corner
 */
export class Toast {
  static container = null

  /**
   * Initialize toast container
   */
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
      gap: 12px;
      pointer-events: none;
    `
    document.body.appendChild(Toast.container)

    // Add CSS animations
    Toast.addStyles()
  }

  /**
   * Add CSS animations for toasts
   */
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

      .toast {
        pointer-events: auto;
        animation: toast-slide-in 0.3s ease-out;
      }

      .toast.removing {
        animation: toast-slide-out 0.3s ease-out;
      }
    `
    document.head.appendChild(style)
  }

  /**
   * Show toast notification
   * @param {string} message - Message to display
   * @param {string} type - Toast type: 'success', 'error', 'info', 'warning'
   * @param {number} duration - Duration in milliseconds (default 3000)
   */
  static show(message, type = "info", duration = 3000) {
    Toast.init()

    const toast = document.createElement("div")
    toast.className = `toast toast-${type}`
    toast.textContent = message

    toast.style.cssText = `
      padding: 12px 20px;
      background: ${Toast.getBackgroundColor(type)};
      color: white;
      border-radius: 8px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
      font-size: 14px;
      font-weight: 500;
      max-width: 300px;
      line-height: 1.4;
    `

    Toast.container.appendChild(toast)

    // Auto dismiss after duration
    if (duration > 0) {
      setTimeout(() => {
        Toast.dismiss(toast)
      }, duration)
    }

    return toast
  }

  /**
   * Dismiss a toast
   * @param {HTMLElement} toast - Toast element to dismiss
   */
  static dismiss(toast) {
    toast.classList.add("removing")
    setTimeout(() => {
      toast.remove()
    }, 300)
  }

  /**
   * Get background color for toast type
   * @param {string} type - Toast type
   * @returns {string} CSS color
   */
  static getBackgroundColor(type) {
    const colors = {
      success: "#22c55e",
      error: "#ef4444",
      warning: "#f59e0b",
      info: "#3b82f6",
    }
    return colors[type] || colors.info
  }

  /**
   * Show success toast
   * @param {string} message
   * @param {number} duration
   */
  static success(message, duration = 3000) {
    return Toast.show(message, "success", duration)
  }

  /**
   * Show error toast
   * @param {string} message
   * @param {number} duration
   */
  static error(message, duration = 4000) {
    return Toast.show(message, "error", duration)
  }

  /**
   * Show warning toast
   * @param {string} message
   * @param {number} duration
   */
  static warning(message, duration = 3500) {
    return Toast.show(message, "warning", duration)
  }

  /**
   * Show info toast
   * @param {string} message
   * @param {number} duration
   */
  static info(message, duration = 3000) {
    return Toast.show(message, "info", duration)
  }

  /**
   * Clear all toasts
   */
  static clearAll() {
    if (!Toast.container) return

    const toasts = Toast.container.querySelectorAll(".toast")
    toasts.forEach((toast) => {
      Toast.dismiss(toast)
    })
  }
}
