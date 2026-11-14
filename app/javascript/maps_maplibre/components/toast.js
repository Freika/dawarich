/**
 * Toast notification system
 * Quiet notes at the bottom centre of the screen. On the map they sit at the
 * top, under the loading badge, centred on the part of the map in view. The
 * surface follows the theme; only a small dot carries the type's colour.
 */
export class Toast {
  static container = null

  static init() {
    const dock = document.querySelector(".map-toast-stack")
    const host = dock || document.body
    // Turbo replaces the page, so a container from an earlier page is gone.
    if (Toast.container?.isConnected && Toast.container.parentElement === host)
      return

    Toast.container?.remove()
    Toast.container = document.createElement("div")
    Toast.container.className = dock
      ? "toast-container toast-container--docked"
      : "toast-container"
    Toast.container.setAttribute("role", "status")
    Toast.container.setAttribute("aria-live", "polite")
    if (dock) dock.prepend(Toast.container)
    else document.body.appendChild(Toast.container)

    Toast.addStyles()
  }

  static addStyles() {
    if (document.getElementById("toast-styles")) return

    const style = document.createElement("style")
    style.id = "toast-styles"
    style.textContent = `
      @keyframes toast-in {
        from { transform: translateY(8px); opacity: 0; }
        to { transform: translateY(0); opacity: 1; }
      }

      .toast-container {
        position: fixed;
        bottom: 72px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 9999;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
        width: max-content;
        max-width: calc(100vw - 32px);
        pointer-events: none;
      }

      .toast-container--docked {
        position: static;
        transform: none;
        width: auto;
        max-width: 100%;
      }

      @keyframes toast-in-top {
        from { transform: translateY(-8px); opacity: 0; }
        to { transform: translateY(0); opacity: 1; }
      }

      .toast-container--docked > .toast {
        animation-name: toast-in-top;
      }

      .toast-container--docked > .toast.removing {
        transform: translateY(-8px);
      }

      .toast-container > .toast {
        position: relative;
        inset: auto;
        transform: none;
        display: flex;
        flex-direction: row;
        flex-wrap: wrap;
        align-items: center;
        gap: 10px;
        min-width: 0;
        max-width: min(420px, calc(100vw - 32px));
        padding: 8px 14px;
        border: 1px solid oklch(var(--bc) / 0.12);
        border-radius: 10px;
        background: oklch(var(--b1) / 0.97);
        color: oklch(var(--bc));
        box-shadow: 0 6px 20px rgb(0 0 0 / 0.18);
        font-size: 13px;
        line-height: 1.4;
        white-space: normal;
        pointer-events: none;
        animation: toast-in 0.2s ease-out;
        transition: opacity 0.2s ease-out, transform 0.2s ease-out;
      }

      .toast-container > .toast::before {
        content: "";
        flex: none;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: oklch(var(--in));
      }

      .toast-container > .toast-success::before { background: oklch(var(--su)); }
      .toast-container > .toast-error::before { background: oklch(var(--er)); }
      .toast-container > .toast-warning::before { background: oklch(var(--wa)); }

      .toast-container > .toast span {
        flex: 1;
        min-width: 0;
        overflow-wrap: anywhere;
      }

      .toast-container > .toast button {
        pointer-events: auto;
        padding: 2px 8px;
        border: 1px solid oklch(var(--bc) / 0.25);
        border-radius: 6px;
        font-weight: 600;
        white-space: normal;
        overflow-wrap: anywhere;
      }

      .toast-container > .toast.removing {
        opacity: 0;
        transform: translateY(8px);
      }

      @media (prefers-reduced-motion: reduce) {
        .toast-container > .toast { animation: none; transition: none; }
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
  static show(message, type = "info", duration = 3000, action = null) {
    Toast.init()

    const toast = document.createElement("div")
    toast.className = `toast toast-${type}`
    const messageElement = document.createElement("span")
    messageElement.textContent = message
    toast.appendChild(messageElement)

    if (action?.label && action?.callback) {
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = action.label
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

  /**
   * Dismiss a toast
   * @param {HTMLElement} toast - Toast element to dismiss
   */
  static dismiss(toast) {
    if (!toast?.parentNode) return

    toast.classList.add("removing")
    setTimeout(() => {
      toast.remove()
    }, 300)
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

  static retry(message, label, callback) {
    return Toast.show(message, "error", 0, { label, callback })
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
}
