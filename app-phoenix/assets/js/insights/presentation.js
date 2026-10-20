function lazy(name) {
  return {
    async mounted() {
      this.insightsAlive = true
      const run = this.insightsRun = (this.insightsRun || 0) + 1
      const module = await import("./presentation_runtime.js")
      if (!this.insightsAlive || run !== this.insightsRun) return
      this.insightsOwner = module[name]
      this.insightsOwner.mounted.call(this)
    },
    updated() { this.insightsOwner?.updated.call(this) },
    destroyed() {
      this.insightsAlive = false
      this.insightsRun = (this.insightsRun || 0) + 1
      this.insightsOwner?.destroyed.call(this)
      this.insightsOwner = null
    },
  }
}
export const InsightsCalendar = lazy("InsightsCalendar")
export const InsightsRace = lazy("InsightsRace")
