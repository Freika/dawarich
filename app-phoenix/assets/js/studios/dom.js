const nativeSelector = (selector) =>
  selector.replace(/\[data-(poster|video)-/g, "[data-native-$1-")

export const studioQuery = (root, selector) =>
  root.querySelector(root.dataset?.nativeStudio ? nativeSelector(selector) : selector)

export const studioQueryAll = (root, selector) =>
  [...root.querySelectorAll(root.dataset?.nativeStudio ? nativeSelector(selector) : selector)]

export const studioValue = (element, name) =>
  element.dataset[`native${name[0].toUpperCase()}${name.slice(1)}`] ?? element.dataset[name]

export function studioPanel(root, dialog) {
  if (dialog) return dialog
  return {
    get open() { return !root.classList.contains("hidden") },
    showModal() {
      if (this.open) return
      root.classList.remove("hidden")
      if (root.showPopover) {
        root.popover = "manual"
        Object.assign(root.style, { margin: "0", border: "0", padding: "0", width: "100%", height: "100%" })
        root.showPopover()
      }
    },
    close() {
      if (!this.open) return
      root.hidePopover?.()
      root.classList.add("hidden")
    },
    onCancel(close) {
      const escape = (event) => {
        if (event.key === "Escape" && !root.classList.contains("hidden")) {
          event.preventDefault()
          close()
        }
      }
      root.ownerDocument.addEventListener("keydown", escape)
      return () => root.ownerDocument.removeEventListener("keydown", escape)
    },
  }
}
