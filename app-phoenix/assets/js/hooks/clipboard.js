const maxCopyLength = 16384

function fallbackCopy(text) {
  if (text.length > maxCopyLength) return false
  let area
  const previous = document.activeElement
  try {
    area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    Object.assign(area.style, {
      position: "fixed",
      top: "0",
      left: "0",
      opacity: "0",
      pointerEvents: "none",
    })
    document.body.appendChild(area)
    area.focus()
    area.select()
    area.setSelectionRange(0, text.length)
    return document.execCommand("copy") === true
  } catch {
    return false
  } finally {
    if (area) {
      area.value = ""
      document.body.removeChild(area)
    }
    if (previous?.isConnected) previous.focus()
  }
}

export async function copyText(text, current = () => true) {
  if (!current() || text.length > maxCopyLength) return false
  let copied = false
  if (navigator.clipboard && globalThis.window?.isSecureContext) {
    copied = await navigator.clipboard.writeText(text).then(
      () => true,
      () => false,
    )
  }
  return current() && (copied || fallbackCopy(text))
}

export function manualCopy(status, text) {
  if (!status?.insertAdjacentElement || text.length > maxCopyLength)
    return () => {}
  const area = document.createElement("textarea")
  area.value = text
  area.setAttribute("readonly", "")
  area.setAttribute("aria-label", status.textContent)
  area.className = "textarea textarea-bordered block w-full min-w-0 mt-2"
  status.insertAdjacentElement("afterend", area)
  area.focus()
  area.select()
  const clear = () => {
    clearTimeout(timer)
    area.value = ""
    area.remove()
  }
  const timer = setTimeout(clear, 15000)
  return clear
}

export const Clipboard = {
  mounted() {
    this.copy = (event) => {
      event.preventDefault()
      const text = this.el.dataset.clipboardText || ""
      this.write(
        this.el.dataset.clipboardUrl === "true"
          ? new URL(text, window.location.origin).href
          : text,
      )
    }
    this.el.addEventListener("click", this.copy)
  },
  destroyed() {
    this.el.removeEventListener("click", this.copy)
  },
  async write(text) {
    this.report(await copyText(text))
  },
  report(copied) {
    const status = this.status()
    const { copiedLabel, failedLabel } = this.el.dataset
    if (status) status.textContent = copied ? copiedLabel : failedLabel
    if (!copied) return
    this.el.classList.add("btn-success")
    this.el.disabled = true
    window.setTimeout(() => {
      this.el.classList.remove("btn-success")
      this.el.disabled = false
      if (status) status.textContent = ""
    }, 1500)
  },
  status() {
    return document.getElementById(this.el.dataset.statusId)
  },
}
