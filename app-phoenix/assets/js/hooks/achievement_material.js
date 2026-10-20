export const AchievementMaterial = {
  loader: () => import("../achievements/card.js"),
  async mounted() {
    this.departed = false
    const { initializeAchievementCard } = await this.loader()
    if (!this.departed) this.dispose = initializeAchievementCard(this.el)
  },
  destroyed() {
    this.departed = true
    this.dispose?.()
  },
}
