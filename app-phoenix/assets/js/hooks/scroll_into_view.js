export const ScrollIntoView = {
  mounted() {
    this.reveal()
  },
  updated() {
    this.reveal()
  },
  reveal() {
    const current = this.el.querySelector(".tab-active")
    if (!current || this.el.scrollWidth <= this.el.clientWidth) return
    current.scrollIntoView({
      block: "nearest",
      inline: "center",
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "auto"
        : "smooth",
    })
  },
}
