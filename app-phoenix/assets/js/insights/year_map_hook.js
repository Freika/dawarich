export const InsightsYearMap = {
  async mounted() {
    this.yearMapAlive = true
    this.yearMapLoad = (this.yearMapLoad || 0) + 1
    const version = this.yearMapLoad
    this.yearMapConfig = `${this.el.dataset.url}:${this.el.dataset.style}`
    try {
      const { createYearMap } = await import("./year_map.js")
      if (this.yearMapAlive && version === this.yearMapLoad)
        this.yearMap = createYearMap(this.el)
    } catch {
      if (this.yearMapAlive) this.el.dataset.mapState = "failed"
    }
  },
  updated() {
    const config = `${this.el.dataset.url}:${this.el.dataset.style}`
    if (config === this.yearMapConfig) return
    this.yearMap?.destroy()
    this.mounted()
  },
  destroyed() {
    this.yearMapAlive = false
    this.yearMapLoad = (this.yearMapLoad || 0) + 1
    this.yearMap?.destroy()
    this.yearMap = null
  },
}
