export const NativeChart = {
  mounted() {
    this.chartAlive = true
    import("../charts/adapter.js").then(({ createAdapter }) => {
      if (!this.chartAlive) return
      this.chartAdapter = createAdapter(
        this.el.querySelector("[data-chart-plot]"),
      )
      this.updated()
    })
  },
  updated() {
    if (!this.chartAdapter) return
    this.chartAdapter.update(JSON.parse(this.el.dataset.chart)).catch(() => {
      if (this.chartAlive) this.el.dataset.chartStatus = "error"
    })
  },
  destroyed() {
    this.chartAlive = false
    this.chartAdapter?.destroy()
  },
}
