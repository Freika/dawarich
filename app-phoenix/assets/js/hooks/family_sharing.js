export const FamilySharing = {
  mounted() {
    this.change = (event) => {
      const field = event.target.dataset.nativeSharingField
      if (!field) return
      const attrs = {}
      for (const name of ["enabled", "duration", "share_history", "history_window"])
        attrs[name] = this.el.querySelector(`[name="${name}"]`).value
      attrs[field] = event.target.type === "checkbox"
        ? String(event.target.checked) : event.target.value
      const command = this.el.dataset.nativeSharingEvent
      this.pushEvent(command, command === "family:sharing" ? { sharing: attrs } : attrs)
    }
    this.submit = (event) => event.preventDefault()
    this.el.addEventListener("change", this.change)
    this.el.addEventListener("submit", this.submit)
  },
  destroyed() {
    this.el.removeEventListener("change", this.change)
    this.el.removeEventListener("submit", this.submit)
  },
}

export const FamilyInviteScroll = {
  mounted() {
    this.scroll = () => this.el.ownerDocument.getElementById("invite-section")?.scrollIntoView({ behavior: "smooth" })
    this.el.addEventListener("click", this.scroll)
  },
  destroyed() {
    this.el.removeEventListener("click", this.scroll)
  },
}
