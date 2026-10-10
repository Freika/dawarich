export const FamilyConfirm = {
  mounted() {
    this.cancelled = false
    this.cancel = (event) => {
      event?.preventDefault()
      this.cancelled = true
      this.pushEvent("family_cancel_confirm", {})
      this.el.close()
    }
    this.closed = () => {
      if (!this.cancelled && this.el.dataset.pending === "true") this.pushEvent("family_cancel_confirm", {})
      this.cancelled = false
    }
    this.el.addEventListener("cancel", this.cancel)
    this.el.addEventListener("close", this.closed)
  },
  updated() {
    if (this.el.dataset.pending !== "true" && this.el.open) this.el.close()
  },
  destroyed() {
    this.el.removeEventListener("cancel", this.cancel)
    this.el.removeEventListener("close", this.closed)
    if (this.el.open) this.el.close()
  },
}
