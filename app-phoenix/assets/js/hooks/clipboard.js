function fallbackCopy(text) {
  const area = document.createElement("textarea")
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
  let copied = false
  try {
    copied = document.execCommand("copy")
  } catch {
    copied = false
  }
  document.body.removeChild(area)
  return copied
}

export const Clipboard = {
  mounted() {
    this.copy = (event) => {
      event.preventDefault()
      this.write(this.el.dataset.clipboardText || "")
    }
    this.el.addEventListener("click", this.copy)
  },
  destroyed() {
    this.el.removeEventListener("click", this.copy)
  },
  async write(text) {
    let copied = false
    if (navigator.clipboard && window.isSecureContext) {
      copied = await navigator.clipboard.writeText(text).then(
        () => true,
        () => false,
      )
    }
    this.report(copied || fallbackCopy(text))
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
