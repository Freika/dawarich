export const AchievementMaterial = {
  loader: () => import("../achievements/card.js"),
  mounted() {
    this.departed = false
    const mount = () => {
      this.observer?.disconnect()
      if (this.departed || this.materialMount) return this.materialMount
      this.materialMount = this.loader().then(({ initializeAchievementCard }) => {
        if (!this.departed) this.dispose = initializeAchievementCard(this.el)
      })
      return this.materialMount
    }
    if (typeof IntersectionObserver === "undefined" || this.el.closest?.(".ach-modal[open]"))
      return mount()
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) return mount()
      },
      { rootMargin: "160px" },
    )
    this.observer.observe(this.el)
  },
  destroyed() {
    this.departed = true
    this.observer?.disconnect()
    this.dispose?.()
  },
}
