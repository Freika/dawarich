export const LayerToggle = {
  mounted() {
    this.pending = null
    this.layerClick = event => {
      event.stopPropagation()
      const choice = {
        layer: this.el.getAttribute("phx-value-layer"),
        enabled: this.el.checked,
      }
      this.pending = choice
      this.pushEvent(this.el.getAttribute("phx-click"), choice, () => {
        if (this.pending !== choice) return
        this.reconnected()
      })
    }
    this.el.addEventListener("click", this.layerClick)
  },
  beforeUpdate(incoming) {
    if (this.pending === null) return
    incoming.toggleAttribute("checked", this.pending.enabled)
    incoming.checked = this.pending.enabled
  },
  reconnected() {
    this.pending = null
    this.el.checked = this.el.dataset.nativeChecked === "true"
    this.el.toggleAttribute("checked", this.el.checked)
  },
  destroyed() {
    this.pending = null
    this.el.removeEventListener("click", this.layerClick)
  },
}
